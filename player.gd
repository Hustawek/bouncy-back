extends RigidBody2D



@export var torque := 20000.0           # how hard it spins up
@export var max_angular_speed := 15.0   # radians per second



func _physics_process(_delta: float) -> void:
	var direction := Input.get_axis("rotate_left", "rotate_right")
	apply_torque(direction * torque)
	angular_velocity = clamp(angular_velocity, -max_angular_speed, max_angular_speed)
