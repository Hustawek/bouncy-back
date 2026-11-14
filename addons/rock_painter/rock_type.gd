@tool
class_name RockType
extends Resource
## A kind of rock: base shading palette plus a streak pattern.

enum Pattern { SPECKLES = 1, VEINS = 2, BANDS = 4, PATCHES = 8 }

@export var display_name := "Rock"

@export_group("Base palette")
@export var outline_color := Color("2a2a30")
@export var shadow_color := Color("4d4f57")
@export var mid_color := Color("6e7079")
@export var light_color := Color("8f919a")
@export var highlight_color := Color("b3b5bd")

@export_group("Streaks")
## Speckles: scattered flecks. Veins: long wandering lines.
## Bands: wavy horizontal layers. Patches: blobs on top-facing edges (moss).
@export_flags("Speckles", "Veins", "Bands", "Patches") var patterns := 1
## For Patches, list colours dark to light (they follow the shading).
@export var streak_colors := PackedColorArray()
@export_range(0.0, 1.0, 0.01) var density := 0.05
@export_range(1, 8) var width := 1
## Veins only: steps per vein, in pixels.
@export_range(2, 200) var vein_length := 25
## Bands only: distance between bands, in pixels.
@export_range(2.0, 40.0, 0.5) var band_spacing := 7.0


func palette() -> Array[Color]:
	return [shadow_color, mid_color, light_color, highlight_color]
