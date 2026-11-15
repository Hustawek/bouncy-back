@tool
@icon("res://addons/rock_painter/rock_icon.svg")
class_name Rock2D
extends StaticBody2D
## A static rock: collision is exactly `outline`, the pixel-art texture is baked
## into the scene and only rebuilt in the editor when a setting below changes.

const Generator := preload("res://addons/rock_painter/rock_generator.gd")
const DEFAULT_TYPE := preload("res://addons/rock_painter/types/stone.tres")
const DEFAULT_Z_INDEX := -100
const MARKER_COLOR := Color(0.3, 0.85, 1.0)

@export var outline := PackedVector2Array():
	set(v):
		outline = v
		_changed()
@export var rock_type: RockType:
	set(v):
		rock_type = v
		_changed()
@export var rock_seed := 0:
	set(v):
		rock_seed = v
		_changed()
## How deep (px) the visible edge may be bitten inward. 0 = art matches collision exactly.
@export_range(0.0, 6.0, 0.5) var roughness := 2.0:
	set(v):
		roughness = v
		_changed()

## Only the rock's top (relative to its rotation) collides; things pass through
## from below and from the sides.
@export var one_way := false:
	set(v):
		one_way = v
		_apply_collision()
		queue_redraw()
## How deep (px) something may sink into the top and still be pushed up onto it.
@export_range(0.0, 32.0, 0.5) var one_way_margin := 4.0:
	set(v):
		one_way_margin = v
		_apply_collision()

## The generated pixels, saved in the scene as PNG bytes.
@export_storage var baked_png := PackedByteArray():
	set(v):
		baked_png = v
		_texture = null
		if not v.is_empty():
			var img := Image.new()
			if img.load_png_from_buffer(v) == OK:
				_texture = ImageTexture.create_from_image(img)
		queue_redraw()
@export_storage var baked_offset := Vector2.ZERO:
	set(v):
		baked_offset = v
		queue_redraw()

var _collision: CollisionPolygon2D
var _texture: Texture2D


func _init() -> void:
	# Rocks sit far behind the level. Existing rocks saved with the old default
	# (0) pick this up too, because Godot doesn't store default values.
	z_index = DEFAULT_Z_INDEX


func _ready() -> void:
	_collision = CollisionPolygon2D.new()
	add_child(_collision, false, INTERNAL_MODE_FRONT)
	_apply_collision()
	if Engine.is_editor_hint() and baked_png.is_empty() and outline.size() >= 3:
		regenerate()


## Builds {"png", "offset"} without assigning it (used for undoable "Regenerate all").
func build() -> Dictionary:
	var r := Generator.generate_image(outline, rock_seed, rock_type if rock_type else DEFAULT_TYPE, roughness)
	if r.is_empty():
		return {"png": PackedByteArray(), "offset": Vector2.ZERO}
	return {"png": r.image.save_png_to_buffer(), "offset": r.offset}


func regenerate() -> void:
	var r := build()
	baked_offset = r.offset
	baked_png = r.png


func _changed() -> void:
	# Property setters also run while a scene loads (before entering the tree);
	# skip work then, so loading never rebuilds textures.
	if not is_inside_tree():
		return
	_apply_collision()
	if Engine.is_editor_hint():
		regenerate()


func _apply_collision() -> void:
	if _collision == null:
		return
	_collision.polygon = outline
	_collision.one_way_collision = one_way
	_collision.one_way_collision_margin = one_way_margin
	if Engine.is_editor_hint():
		queue_redraw()


func _draw() -> void:
	if _texture:
		draw_texture(_texture, baked_offset)
	if one_way and Engine.is_editor_hint() and outline.size() >= 3:
		_draw_one_way_marker()


## Editor-only: highlight the edges that face up and draw an up arrow above the rock.
func _draw_one_way_marker() -> void:
	var n := outline.size()
	var area := 0.0
	for i in n:
		area += outline[i].cross(outline[(i + 1) % n])
	var top_y := INF
	var sum_x := 0.0
	for i in n:
		var a := outline[i]
		var b := outline[(i + 1) % n]
		var normal := (b - a).orthogonal().normalized()
		if area < 0.0:
			normal = -normal  # make it point outward for either winding
		if normal.y < -0.3:
			draw_line(a, b, MARKER_COLOR, 2.0)
		top_y = minf(top_y, a.y)
		sum_x += a.x
	var tip := Vector2(sum_x / n, top_y - 14.0)
	draw_line(tip + Vector2(0, 10), tip, MARKER_COLOR, 2.0)
	draw_colored_polygon(PackedVector2Array([tip + Vector2(0, -2), tip + Vector2(-5, 4), tip + Vector2(5, 4)]), MARKER_COLOR)
