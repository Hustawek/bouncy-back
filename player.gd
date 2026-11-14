extends CharacterBody2D


@export var rotation_speed := 3.0



func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta



	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var direction := Input.get_axis("rotate_left", "rotate_right")
	rotation += direction * rotation_speed * delta


	move_and_slide()
