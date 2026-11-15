@tool
class_name DirectionZone
extends Area2D
# Drop into a level, pick a direction, and shape the CollisionPolygon2D
# child(ren). When the player enters, they turn to face this direction and
# keep it after leaving.

enum Direction { RIGHT, LEFT }

@export var direction := Direction.RIGHT:
	set(value):
		direction = value
		queue_redraw()

const RIGHT_COLOR := Color(0.2, 0.5, 1.0)
const LEFT_COLOR := Color(1.0, 0.55, 0.1)


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	set_process(false)
	body_entered.connect(_on_body_entered)


func _process(_delta: float) -> void:
	# Editor only: redraw so the tint follows polygon edits.
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		body.set_facing_left(direction == Direction.LEFT)


# Editor-only tint and arrow, so left and right zones are easy to tell apart.
func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var color := LEFT_COLOR if direction == Direction.LEFT else RIGHT_COLOR
	var arrow_dir := Vector2.LEFT if direction == Direction.LEFT else Vector2.RIGHT
	for child in get_children():
		if not (child is CollisionPolygon2D) or child.polygon.size() < 3:
			continue
		var points: PackedVector2Array = child.transform * child.polygon
		if not Geometry2D.triangulate_polygon(points).is_empty():
			draw_colored_polygon(points, Color(color, 0.25))
		var outline := points.duplicate()
		outline.append(points[0])
		draw_polyline(outline, color, 2.0)

		var center := Vector2.ZERO
		for p in points:
			center += p
		center /= points.size()
		var tip := center + arrow_dir * 24.0
		draw_line(center - arrow_dir * 24.0, tip, color, 4.0)
		draw_line(tip, tip - arrow_dir.rotated(0.5) * 12.0, color, 4.0)
		draw_line(tip, tip - arrow_dir.rotated(-0.5) * 12.0, color, 4.0)
