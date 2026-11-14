extends RigidBody2D



@export var torque := 20000.0           # how hard it spins up
@export var max_angular_speed := 15.0   # radians per second
func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)


func _physics_process(_delta: float) -> void:
	var direction := Input.get_axis("rotate_left", "rotate_right")
	apply_torque(direction * torque)
	angular_velocity = clamp(angular_velocity, -max_angular_speed, max_angular_speed)


func _on_back_sensor_body_entered(body: Node2D) -> void:
	apply_central_impulse(Vector2(0, -400))
	
	
func _on_body_entered(body: Node) -> void:
	print("Nastąpiło zderzenie z" + body.name)
