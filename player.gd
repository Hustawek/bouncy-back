extends RigidBody2D



@export var torque := 20000.0           # how hard it spins up
@export var max_angular_speed := 15.0   # radians per second

@export_group("Bounce")
@export_range(0.0, 1.0) var player_weight := 0.5   # 0 = straight out of the surface, 1 = player's up
@export var bounce_base := 300.0          # impulse even on a soft landing
@export var bounce_speed_factor := 0.5    # extra impulse per px/s of impact speed
@export var bounce_max := 900.0           # cap on the total impulse
@export var bounce_cooldown := 0.15       # seconds before another bounce can fire

@onready var _back_sensor: Area2D = $BackSensor
var _cooldown_left := 0.0
var _prev_velocity := Vector2.ZERO


func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)


func _physics_process(_delta: float) -> void:
	var direction := Input.get_axis("rotate_left", "rotate_right")
	apply_torque(direction * torque)
	angular_velocity = clamp(angular_velocity, -max_angular_speed, max_angular_speed)


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	_cooldown_left = maxf(_cooldown_left - state.step, 0.0)
	# Checked every step (not only when the sensor first touches), so the
	# player keeps bouncing even if the back was already on the ground.
	if _cooldown_left == 0.0 and _back_sensor.has_overlapping_bodies() and state.get_contact_count() > 0:
		# Average direction pointing out of the surface(s) we're touching.
		var normal := Vector2.ZERO
		for i in state.get_contact_count():
			normal += state.get_contact_local_normal(i)
		normal = normal.normalized()

		var player_up := -state.transform.y.normalized()
		var dir := (player_up * player_weight + normal * (1.0 - player_weight)).normalized()

		# How fast we were moving into the surface just before touching it.
		var impact_speed := maxf(-_prev_velocity.dot(normal), 0.0)
		var strength := minf(bounce_base + bounce_speed_factor * impact_speed, bounce_max)

		# Replace (not add to) the current velocity, so leftover sliding from
		# the landing doesn't bend the launch away from `dir`.
		state.linear_velocity = dir * (strength / mass)
		_cooldown_left = bounce_cooldown
	_prev_velocity = state.linear_velocity


func _on_body_entered(body: Node) -> void:
	print("Nastąpiło zderzenie z" + body.name)
