class_name Player
extends RigidBody2D



@export var torque := 100000.0           # how hard it spins up while touching something
@export var air_torque := 100000.0       # how hard it spins up while in the air
@export var max_angular_speed := 40.0   # radians per second
@export var spin_drag := 0.0           # how fast spin fades with no key held (1.0 = halves in ~0.7 s, 0 = never)
@export var shift_factor := 1.5
@export_group("Bounce")
@export_range(0.0, 1.0) var player_weight := 0.5   # 0 = straight out of the surface, 1 = player's up
@export var bounce_base := 400.0                   # impulse even on a soft landing
@export var bounce_speed_factor := 0.5             # extra impulse per px/s of impact speed
@export var bounce_max := 700.0           # cap on the total impulse
@export var bounce_cooldown := 0.15       # seconds before another bounce can fire
@export var bounce_spin_factor := 1.0     # spin from an off-center bounce: 0 = none, 1 = realistic
@export_range(0.0, 1.0) var bounce_carry := 0.8   # share of incoming speed along the surface kept: 0 = none, 1 = all
@export_group("Sounds and Animations")
@export var lenght_of_bounce_animation := 0.5
var texture_reset_timer: Timer
@onready var _back_sensor: Area2D = $BackSensor
@onready var _back_shape: CollisionShape2D = $BackSensor/CollisionShape2D
var _cooldown_left := 0.0
var _prev_velocity := Vector2.ZERO

var is_dead := false
var facing_left := false   # set by DirectionZone; mirrors the body


func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	_back_sensor.body_entered.connect(_on_back_sensor_body_entered)
	texture_reset_timer = Timer.new()
	texture_reset_timer.one_shot = true
	texture_reset_timer.timeout.connect(_reset_texture)
	add_child(texture_reset_timer)


var last_collision_point := Vector2.ZERO
func _input(event: InputEvent) -> void:
	if is_dead and event is InputEventKey:
		if event.pressed and not event.echo and event.keycode == KEY_SPACE:
			get_tree().call_deferred(
				"change_scene_to_file",
                "res://levele/level0.tscn"
			)
func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if is_dead:
		return
	if global_position.y > 500:
		die()
		return
	if state.get_contact_count() > 0:
		last_collision_point = state.get_contact_local_position(0)
	# Player spin input: a different torque in the air than on the ground.
	var in_air := state.get_contact_count() == 0
	var direction := Input.get_axis("rotate_left", "rotate_right")
	state.apply_torque(direction * (air_torque if in_air else torque))
	# With no key held, the spin fades out gradually instead of stopping.
	if direction == 0.0:
		state.angular_velocity *= exp(-spin_drag * state.step)

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
	var collider_id: int = hit["collider_id"]
	var collider := instance_from_id(collider_id) as CollisionObject2D
	#if collider.name.begins_with("Wieza"):
		#strength *= 1.5
	var impulse := dir * strength

	# Launch velocity plus part of the incoming speed along the surface, so
	# sliding/flying sideways into a bounce keeps some of that momentum.
	# Uses the previous step's velocity: on this step the collision has
	# already eaten into it.
	var along_surface := _prev_velocity - _prev_velocity.dot(normal) * normal
	state.linear_velocity = impulse / mass + along_surface * bounce_carry

	# The push comes from where the back touches, not from the center, so an
	# off-center touch spins the player (same formula Godot uses for impulses).
	var lever: Vector2 = hit["point"] - (state.transform.origin + state.center_of_mass)
	state.angular_velocity += lever.cross(impulse) * state.inverse_inertia * bounce_spin_factor

	_cooldown_left = bounce_cooldown
	$JumpSound.play()
	$PL.texture = load("res://sprites/jakisBullshit2.png")
	texture_reset_timer.start(lenght_of_bounce_animation)
func _reset_texture() -> void:
	$PL.texture = load("res://sprites/jakisBullshit1.png")

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


# Called by DirectionZone. Only acts when the direction actually changes.
func set_facing_left(left: bool) -> void:
	if left == facing_left or is_dead:
		return
	facing_left = left
	# Zones report the player while physics is busy, when shapes can't be
	# moved, so flip at the end of the frame.
	_mirror.call_deferred()


# Mirrors the player left-to-right on screen. Physics bodies can't use a
# negative scale, so every transform in the tree is mirrored instead: x
# position and rotation are negated, and sprites also get flipped. The
# capsules are symmetric, so they need no flip of their own.
func _mirror() -> void:
	if is_dead:
		return
	_mirror_children(self)
	rotation = -rotation
	angular_velocity = -angular_velocity


func _mirror_children(node: Node) -> void:
	for child in node.get_children():
		if child is Node2D:
			child.position.x = -child.position.x
			child.rotation = -child.rotation
			if child is Sprite2D:
				child.flip_h = not child.flip_h
		_mirror_children(child)


func die() -> void:
	if is_dead:
		return

	is_dead = true

	# Show death UI
	$SkillO.show()

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
	if str(body.name).begins_with("Spike"):
		die()
func _on_back_sensor_body_entered(body: Node) -> void:
	if str(body.name).begins_with("Spike"):
		die()
	if str(body.name).begins_with("Wieza"):
		body.queue_free()
