extends Area2D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	body_entered.connect(_a) # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _a(b: Node) -> void:
	if b.name == "Player":
		get_tree().change_scene_to_file("res://finish.tscn")
