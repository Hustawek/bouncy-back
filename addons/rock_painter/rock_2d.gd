@tool
@icon("res://addons/rock_painter/rock_icon.svg")
class_name Rock2D
extends StaticBody2D
## A static rock: collision is exactly `outline`, the pixel-art texture is baked
## into the scene and only rebuilt in the editor when a setting below changes.

const Generator := preload("res://addons/rock_painter/rock_generator.gd")
const DEFAULT_TYPE := preload("res://addons/rock_painter/types/stone.tres")

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


func _ready() -> void:
	_collision = CollisionPolygon2D.new()
	add_child(_collision, false, INTERNAL_MODE_FRONT)
	_collision.polygon = outline
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
	if _collision:
		_collision.polygon = outline
	if Engine.is_editor_hint():
		regenerate()


func _draw() -> void:
	if _texture:
		draw_texture(_texture, baked_offset)
