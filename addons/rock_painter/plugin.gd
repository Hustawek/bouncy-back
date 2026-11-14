@tool
extends EditorPlugin

const Rock2DScript := preload("res://addons/rock_painter/rock_2d.gd")
const TYPES_DIR := "res://addons/rock_painter/types/"
const POINT_SPACING_SCREEN := 3.0   # px on screen between recorded stroke points
const SIMPLIFY_SCREEN := 1.5        # px on screen a simplified outline may deviate
const MIN_AREA := 16.0              # px², smaller strokes are ignored
const STROKE_COLOR := Color(1.0, 0.75, 0.2)

var _toolbar: HBoxContainer
var _draw_button: Button
var _type_picker: OptionButton
var _types: Array[RockType] = []
var _edited: Node
var _drawing := false
var _stroke := PackedVector2Array()  # canvas (scene-global) coordinates


func _enter_tree() -> void:
	_toolbar = HBoxContainer.new()
	_toolbar.add_child(VSeparator.new())

	_draw_button = Button.new()
	_draw_button.text = "Draw Rock"
	_draw_button.toggle_mode = true
	_draw_button.flat = true
	_draw_button.tooltip_text = "Drag a closed loop in the 2D view to create a rock.\nRight-click or Esc cancels a stroke."
	_draw_button.toggled.connect(_on_draw_toggled)
	_toolbar.add_child(_draw_button)

	_type_picker = OptionButton.new()
	_type_picker.tooltip_text = "Rock type for new rocks (from %s)" % TYPES_DIR
	_toolbar.add_child(_type_picker)

	var seed_button := Button.new()
	seed_button.text = "New Seed"
	seed_button.flat = true
	seed_button.tooltip_text = "Re-roll the look of the selected rock(s)."
	seed_button.pressed.connect(_on_new_seed)
	_toolbar.add_child(seed_button)

	var regen_button := Button.new()
	regen_button.text = "Regenerate All Rocks"
	regen_button.flat = true
	regen_button.tooltip_text = "Rebuild every rock in this scene from its current type\n(use after editing a rock type's colours)."
	regen_button.pressed.connect(_on_regenerate_all)
	_toolbar.add_child(regen_button)

	add_control_to_container(CONTAINER_CANVAS_EDITOR_MENU, _toolbar)
	_scan_types()
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(_scan_types)


func _exit_tree() -> void:
	EditorInterface.get_resource_filesystem().filesystem_changed.disconnect(_scan_types)
	remove_control_from_container(CONTAINER_CANVAS_EDITOR_MENU, _toolbar)
	_toolbar.queue_free()


# The 2D editor only forwards mouse input to plugins that handle the selected
# node, so we claim every node (we ignore input unless Draw Rock is on).
func _handles(object: Object) -> bool:
	return object is Node


func _edit(object: Object) -> void:
	_edited = object as Node


func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if not _draw_button.button_pressed or EditorInterface.get_edited_scene_root() == null:
		return false
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_drawing = true
				_stroke = PackedVector2Array([_to_canvas(event.position)])
			elif _drawing:
				_drawing = false
				_finish_stroke()
			update_overlays()
			return true
		if event.button_index == MOUSE_BUTTON_RIGHT and _drawing:
			_cancel_stroke()
			return true
	elif event is InputEventMouseMotion and _drawing:
		var p := _to_canvas(event.position)
		if _stroke[-1].distance_to(p) * _zoom() >= POINT_SPACING_SCREEN:
			_stroke.append(p)
			update_overlays()
		return true
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and _drawing:
		_cancel_stroke()
		return true
	return false


func _forward_canvas_draw_over_viewport(overlay: Control) -> void:
	if not _draw_button.button_pressed:
		return
	overlay.draw_string(overlay.get_theme_default_font(), Vector2(12, overlay.size.y - 12),
		"Rock Painter: drag a loop to add a rock (%s)" % _type_picker.get_item_text(_type_picker.selected),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, STROKE_COLOR)
	if _drawing and _stroke.size() > 1:
		var xf := _canvas_xform()
		var pts := PackedVector2Array()
		for p in _stroke:
			pts.append(xf * p)
		pts.append(pts[0])
		overlay.draw_polyline(pts, STROKE_COLOR, 2.0, true)


func _on_draw_toggled(on: bool) -> void:
	_drawing = false
	var root := EditorInterface.get_edited_scene_root()
	if on and root and EditorInterface.get_selection().get_selected_nodes().is_empty():
		# Nothing selected means no input reaches us; select the root.
		EditorInterface.get_selection().add_node(root)
	update_overlays()


func _cancel_stroke() -> void:
	_drawing = false
	_stroke.clear()
	update_overlays()


func _finish_stroke() -> void:
	var stroke := _stroke
	_stroke = PackedVector2Array()
	if stroke.size() < 3:
		return
	var closed := stroke.duplicate()
	closed.append(stroke[0])
	var pts := _rdp(closed, SIMPLIFY_SCREEN / _zoom())
	pts.remove_at(pts.size() - 1)
	if pts.size() < 3 or absf(_area(pts)) < MIN_AREA:
		return
	if _self_intersects(pts):
		push_warning("Rock Painter: that outline crosses itself; draw a loop that doesn't cross.")
		return

	var root := EditorInterface.get_edited_scene_root()
	var parent := _target_parent(root)
	var to_local := Transform2D.IDENTITY
	if parent is CanvasItem:
		to_local = (parent as CanvasItem).get_global_transform().affine_inverse()
	var center := Vector2.ZERO
	for i in pts.size():
		pts[i] = to_local * pts[i]
		center += pts[i]
	center = (center / pts.size()).round()
	for i in pts.size():
		pts[i] -= center

	var rock = Rock2DScript.new()
	rock.name = "Rock"
	rock.position = center
	rock.rock_type = _current_type()
	rock.rock_seed = randi()
	rock.outline = pts

	var ur := get_undo_redo()
	ur.create_action("Draw Rock", UndoRedo.MERGE_DISABLE, root)
	ur.add_do_method(parent, "add_child", rock, true)
	ur.add_do_property(rock, "owner", root)
	ur.add_do_reference(rock)
	ur.add_undo_method(parent, "remove_child", rock)
	ur.commit_action()

	var sel := EditorInterface.get_selection()
	sel.clear()
	sel.add_node(rock)


## New rocks go under the selected node; if that's a rock, next to it.
## Nodes inside instanced sub-scenes are skipped up to a node this scene owns.
func _target_parent(root: Node) -> Node:
	var parent := _edited
	if parent == null or not is_instance_valid(parent) or not (parent == root or root.is_ancestor_of(parent)):
		return root
	if parent.get_script() == Rock2DScript and parent != root:
		parent = parent.get_parent()
	while parent != root and parent.owner != root:
		parent = parent.get_parent()
	return parent


func _on_new_seed() -> void:
	var rocks := _selected_rocks()
	if rocks.is_empty():
		return
	var ur := get_undo_redo()
	ur.create_action("New Rock Seed", UndoRedo.MERGE_DISABLE, EditorInterface.get_edited_scene_root())
	for r in rocks:
		ur.add_do_property(r, "rock_seed", randi())
		ur.add_undo_property(r, "rock_seed", r.rock_seed)
	ur.commit_action()


func _on_regenerate_all() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return
	var rocks: Array[Node] = []
	_collect_rocks(root, rocks)
	if rocks.is_empty():
		return
	var ur := get_undo_redo()
	ur.create_action("Regenerate All Rocks", UndoRedo.MERGE_DISABLE, root)
	for r in rocks:
		var built: Dictionary = r.build()
		ur.add_do_property(r, "baked_png", built.png)
		ur.add_do_property(r, "baked_offset", built.offset)
		ur.add_undo_property(r, "baked_png", r.baked_png)
		ur.add_undo_property(r, "baked_offset", r.baked_offset)
	ur.commit_action()
	print("Rock Painter: regenerated %d rock(s)." % rocks.size())


func _collect_rocks(node: Node, out: Array[Node]) -> void:
	if node.get_script() == Rock2DScript:
		out.append(node)
	for c in node.get_children():
		_collect_rocks(c, out)


func _selected_rocks() -> Array[Node]:
	var out: Array[Node] = []
	for n in EditorInterface.get_selection().get_selected_nodes():
		if n.get_script() == Rock2DScript:
			out.append(n)
	return out


func _scan_types() -> void:
	var previous := _type_picker.get_item_text(_type_picker.selected) if _type_picker.item_count else "Stone"
	_types.clear()
	_type_picker.clear()
	for f in DirAccess.get_files_at(TYPES_DIR):
		if f.ends_with(".tres"):
			var t := load(TYPES_DIR + f) as RockType
			if t:
				_types.append(t)
	_types.sort_custom(func(a, b): return a.display_name < b.display_name)
	for t in _types:
		_type_picker.add_item(t.display_name)
		if t.display_name == previous:
			_type_picker.select(_type_picker.item_count - 1)


func _current_type() -> RockType:
	if _types.is_empty():
		return null
	return _types[clampi(_type_picker.selected, 0, _types.size() - 1)]


func _canvas_xform() -> Transform2D:
	return EditorInterface.get_editor_viewport_2d().global_canvas_transform


func _to_canvas(screen_pos: Vector2) -> Vector2:
	return _canvas_xform().affine_inverse() * screen_pos


func _zoom() -> float:
	return _canvas_xform().get_scale().x


## Ramer–Douglas–Peucker simplification of an open polyline.
static func _rdp(pts: PackedVector2Array, eps: float) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var a := pts[0]
	var b := pts[-1]
	var max_d := -1.0
	var idx := 0
	for i in range(1, pts.size() - 1):
		var d := pts[i].distance_to(Geometry2D.get_closest_point_to_segment(pts[i], a, b))
		if d > max_d:
			max_d = d
			idx = i
	if max_d <= eps:
		return PackedVector2Array([a, b])
	var left := _rdp(pts.slice(0, idx + 1), eps)
	var right := _rdp(pts.slice(idx), eps)
	left.remove_at(left.size() - 1)
	return left + right


static func _area(pts: PackedVector2Array) -> float:
	var s := 0.0
	for i in pts.size():
		s += pts[i].cross(pts[(i + 1) % pts.size()])
	return s * 0.5


static func _self_intersects(pts: PackedVector2Array) -> bool:
	var n := pts.size()
	for i in n:
		for j in range(i + 2, n):
			if i == 0 and j == n - 1:
				continue  # neighbours via the closing edge
			if Geometry2D.segment_intersects_segment(pts[i], pts[(i + 1) % n], pts[j], pts[(j + 1) % n]) != null:
				return true
	return false
