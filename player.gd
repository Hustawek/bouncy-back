extends RigidBody2D



@export var torque := 200000.0           # how hard it spins up while touching something
@export var air_torque := 200000.0       # how hard it spins up while in the air
@export var max_angular_speed := 100.0   # radians per second

@export_group("Bounce")
@export_range(0.0, 1.0) var player_weight := 0.5   # 0 = straight out of the surface, 1 = player's up
@export var bounce_base := 400.0                   # impulse even on a soft landing
@export var bounce_speed_factor := 0.5             # extra impulse per px/s of impact speed
@export var bounce_max := 700.0           # cap on the total impulse
@export var bounce_cooldown := 0.15       # seconds before another bounce can fire
@export var bounce_spin_factor := 1.0     # spin from an off-center bounce: 0 = none, 1 = realistic

@onready var _back_sensor: Area2D = $BackSensor
@onready var _back_shape: CollisionShape2D = $BackSensor/CollisionShape2D
var _cooldown_left := 0.0
var _prev_velocity := Vector2.ZERO

var is_dead := false


func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	_back_sensor.body_entered.connect(_on_back_sensor_body_entered)


var last_collision_point := Vector2.ZERO

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if is_dead:
		return
	if state.get_contact_count() > 0:
		last_collision_point = state.get_contact_local_position(0)
	# Player spin input: a different torque in the air than on the ground.
	var in_air := state.get_contact_count() == 0
	var direction := Input.get_axis("rotate_left", "rotate_right")
	state.apply_torque(direction * (air_torque if in_air else torque))

	_cooldown_left = maxf(_cooldown_left - state.step, 0.0)
	# Checked every step (not only when the sensor first touches), so the
	# player keeps bouncing even if the back was already on the ground.
	if _cooldown_left == 0.0 and _back_sensor.has_overlapping_bodies():
		_try_bounce(state)

	# Cap the spin here (not in _physics_process), after input and bounce,
	# so the physics step can't overwrite it.
	state.angular_velocity = clampf(state.angular_velocity, -max_angular_speed, max_angular_speed)
	_prev_velocity = state.linear_velocity


func _try_bounce(state: PhysicsDirectBodyState2D) -> void:
	# Where and at what angle the BackSensor touches a surface, taken from the
	# sensor's own shape (the body's contacts don't matter).
	var hit := _back_sensor_hit(state)
	if hit.is_empty():
		return  # sensor overlap is a step stale; nothing under it this step
	var normal: Vector2 = hit["normal"]

	var player_up := -state.transform.y.normalized()
	var dir := (player_up * player_weight + normal * (1.0 - player_weight)).normalized()

	# How fast we were moving into the surface just before touching it.
	var impact_speed := maxf(-_prev_velocity.dot(normal), 0.0)
	var strength := minf(bounce_base + bounce_speed_factor * impact_speed, bounce_max)
	var impulse := dir * strength

	# Replace (not add to) the current velocity, so leftover sliding from
	# the landing doesn't bend the launch away from `dir`.
	state.linear_velocity = impulse / mass

	# The push comes from where the back touches, not from the center, so an
	# off-center touch spins the player (same formula Godot uses for impulses).
	var lever: Vector2 = hit["point"] - (state.transform.origin + state.center_of_mass)
	state.angular_velocity += lever.cross(impulse) * state.inverse_inertia * bounce_spin_factor

	_cooldown_left = bounce_cooldown


# Asks the physics engine where the BackSensor's shape touches something.
# Returns {} if it touches nothing, otherwise a dictionary with "point" and
# "normal" (the surface's outward direction).
# Uses state.transform (this step's pose) rather than global_transform, which
# still holds the previous step's pose while the body is moving fast.
func _back_sensor_hit(state: PhysicsDirectBodyState2D) -> Dictionary:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _back_shape.shape
	query.transform = state.transform * _back_sensor.transform * _back_shape.transform
	query.collision_mask = _back_sensor.collision_mask
	query.exclude = [get_rid()]
	return state.get_space_state().get_rest_info(query)
	
func die() -> void:
	if is_dead:
		return

	is_dead = true

	# Show death UI
	$"../CanvasLayer/CenterContainer/Skill".show()

	# Show Uranium
	var uranium := $Uranium
	uranium.reparent(get_tree().current_scene, true)
	uranium.global_position = last_collision_point
	uranium.show()

	# Stop all physics movement
	set_deferred("linear_velocity", Vector2.ZERO)
	set_deferred("angular_velocity", 0.0)
	set_deferred("freeze", true)

	# Disable collisions
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	set_deferred("contact_monitor", false)

	# Disable the back sensor
	_back_sensor.set_deferred("monitoring", false)
	_back_sensor.set_deferred("monitorable", false)

func _on_body_entered(body: Node) -> void:
	if str(body.name).begins_with("Wieza"):
		die()
	if str(body.name).begins_with("Spike"):
		die()
func _on_back_sensor_body_entered(body: Node) -> void:
	if str(body.name).begins_with("Spike"):
		die()
	if str(body.name).begins_with("Wieza"):
		body.queue_free()
