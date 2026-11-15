extends Control

@onready var play_button = $Play
@onready var exit_button = $Exit

func _ready():
	play_button.pressed.connect(_on_play_pressed)
	exit_button.pressed.connect(_on_exit_pressed)


func _on_play_pressed():
	get_tree().change_scene_to_file("res://levele/level0.tscn")


func _on_exit_pressed():
	get_tree().quit()
