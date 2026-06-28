extends CharacterBody3D
## Tethered — first-person climbing controller with White Knuckle-style climbing.
##
## Core verbs:
##   LMB (hold)  — grab with LEFT hand (ray from camera-left)
##   RMB (hold)  — grab with RIGHT hand (ray from camera-right)
##   Mouse       — look around / aim hands
##   WASD        — walk (ground) / pump swing (1 hand) / shimmy (2 hands)
##   Space       — jump (ground) / launch off swing (1 hand) / push off (2 hands)
##   E (hold)    — sprint (ground)
##   T           — toggle tether (handled by HUD)
##   R           — restart run (handled by HUD)
##
## Climbing model:
##   - Each hand fires its own raycast. A hand is either FREE or ANCHORED at a
##     world-space point.
##   - 0 hands anchored  → normal walking/falling.
##   - 1 hand anchored   → PENDULUM: swing on a rope of length = distance to
##                          anchor. WASD pumps the swing. Space launches you
##                          with momentum + upward boost.
##   - 2 hands anchored   → CLIMBING: body is pulled toward the midpoint of the
##                          two anchors (you hang near your grips). W/S moves
##                          up/down along the anchor line. A/D shimmies sideways.
##                          Space releases both hands and pushes you up+forward
##                          — if you aimed at a ledge, you naturally clear it
##                          and land on top. MANUAL mantling, no auto-teleport.
##
## Stamina:
##   - Gripping drains stamina. 1 hand = slow drain, 2 hands = faster.
##   - Launching/pushing off costs a burst. Running out = forced release.
##   - Regenerates when both hands free and on ground.

@export var move_speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var air_control: float = 0.3
@export var jump_velocity: float = 6.0
@export var mouse_sensitivity: float = 0.0025
@export var gravity: float = 18.0

## Climbing / swing tuning.
@export var swing_gravity: float = 5.0
@export var swing_pump_force: float = 10.0
@export var launch_force: float = 1.0
@export var launch_boost: float = 2.5
@export var climb_speed: float = 4.0
@export var shimmy_speed: float = 3.0
@export var max_reach: float = 3.0

## Two-hand pull: how strongly the body is drawn toward the anchor midpoint.
@export var pull_to_anchors_strength: float = 8.0
## Push-off force when releasing both hands (manual mantle jump).
@export var push_off_up: float = 5.0
@export var push_off_forward: float = 4.0

## Stamina.
@export var max_stamina: float = 100.0
@export var stamina_drain_one_hand: float = 4.0
@export var stamina_drain_two_hands: float = 7.0
@export var stamina_drain_launch: float = 15.0
@export var stamina_regen: float = 15.0
@export var stamina_min_grip: float = 5.0

## External force accumulator (tether pulls).
var external_force: Vector3 = Vector3.ZERO

var stamina: float = 100.0

## Hand states.
enum HandState { FREE, ANCHORED }
var left_state: HandState = HandState.FREE
var right_state: HandState = HandState.FREE
var left_anchor: Vector3 = Vector3.ZERO
var right_anchor: Vector3 = Vector3.ZERO
var left_rope_len: float = 0.0
var right_rope_len: float = 0.0

## Swing velocity (tangential, used when 1 hand anchored).
var swing_vel: Vector3 = Vector3.ZERO

@onready var camera: Camera3D = $Camera3D
@onready var left_ray: RayCast3D = $Camera3D/LeftRay
@onready var right_ray: RayCast3D = $Camera3D/RightRay


func _ready() -> void:
	GameManager.register_player(self)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	stamina = max_stamina


func _exit_tree() -> void:
	GameManager.unregister_player(self)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		camera.rotation.x = clampf(camera.rotation.x, -PI / 2.0, PI / 2.0)
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	_update_hands()
	_process_stamina(delta)

	var anchored_count := _anchored_count()
	match anchored_count:
		0:
			_free_movement(delta)
		1:
			_swing_movement(delta)
		2:
			_climb_movement(delta)

	# Apply tether/external force then reset.
	velocity += external_force * delta
	external_force = Vector3.ZERO
	move_and_slide()


# ─── Hand management ─────────────────────────────────────────────────────────

func _update_hands() -> void:
	if Input.is_action_just_pressed("grab_left"):
		_try_grab_hand(true)
	if Input.is_action_just_released("grab_left"):
		_release_hand(true)
	if Input.is_action_just_pressed("grab_right"):
		_try_grab_hand(false)
	if Input.is_action_just_released("grab_right"):
		_release_hand(false)


func _try_grab_hand(is_left: bool) -> void:
	var ray := left_ray if is_left else right_ray
	if not ray.is_colliding():
		return
	if stamina < stamina_min_grip:
		return

	var point := ray.get_collision_point()
	var dist := global_position.distance_to(point)
	if dist > max_reach:
		return

	if is_left:
		left_state = HandState.ANCHORED
		left_anchor = point
		left_rope_len = dist
	else:
		right_state = HandState.ANCHORED
		right_anchor = point
		right_rope_len = dist

	# When transitioning from free→anchored, absorb current velocity into swing.
	if _anchored_count() == 1:
		swing_vel = velocity
		velocity = Vector3.ZERO


func _release_hand(is_left: bool) -> void:
	if is_left:
		left_state = HandState.FREE
	else:
		right_state = HandState.FREE


func _anchored_count() -> int:
	var c := 0
	if left_state == HandState.ANCHORED: c += 1
	if right_state == HandState.ANCHORED: c += 1
	return c


# ─── Movement modes ─────────────────────────────────────────────────────────

func _free_movement(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	var speed := move_speed
	var control := 1.0 if is_on_floor() else air_control
	if direction:
		var target := direction * speed
		velocity.x = lerpf(velocity.x, target.x, control)
		velocity.z = lerpf(velocity.z, target.z, control)
	elif is_on_floor():
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	# Sprint.
	if Input.is_action_pressed("interact") and is_on_floor() and direction:
		velocity.x = direction.x * sprint_speed
		velocity.z = direction.z * sprint_speed

	# Jump from ground.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity


func _swing_movement(delta: float) -> void:
	## One hand anchored → pendulum physics.
	var anchor := left_anchor if left_state == HandState.ANCHORED else right_anchor
	var rope_len := left_rope_len if left_state == HandState.ANCHORED else right_rope_len

	var to_anchor := anchor - global_position
	var dist := to_anchor.length()
	if dist < 0.01:
		return
	var radial_dir := to_anchor / dist

	# Gravity.
	swing_vel.y -= swing_gravity * delta

	# Pump force: WASD adds tangential force.
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var wish := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if wish.length_squared() > 0.01:
		var tangential := wish - radial_dir * wish.dot(radial_dir)
		if tangential.length_squared() > 0.001:
			tangential = tangential.normalized()
			swing_vel += tangential * swing_pump_force * delta

	# Hard constraint: stay on sphere of radius rope_len.
	var new_pos := global_position + swing_vel * delta
	var to_new := new_pos - anchor
	if to_new.length() > rope_len:
		to_new = to_new.normalized() * rope_len
		new_pos = anchor + to_new
		var radial := to_new.normalized()
		swing_vel -= radial * swing_vel.dot(radial)

	global_position = new_pos
	velocity = swing_vel

	# Launch: space releases the hand and applies momentum + upward boost.
	if Input.is_action_just_pressed("jump"):
		if stamina >= stamina_drain_launch:
			swing_vel += Vector3.UP * launch_boost
			velocity = swing_vel * launch_force
			stamina -= stamina_drain_launch
			_release_hand(left_state == HandState.ANCHORED)
			swing_vel = Vector3.ZERO


func _climb_movement(delta: float) -> void:
	## Both hands anchored → climb along the line between anchors + shimmy.
	## Body is pulled toward the anchor midpoint and constrained to arm's reach.
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")

	# Direction from lower to higher anchor.
	var a := left_anchor
	var b := right_anchor
	var up_dir := (b - a).normalized() if b.y > a.y else (a - b).normalized()
	# Shimmy direction = perpendicular to up_dir, horizontal.
	var shimmy_dir := up_dir.cross(Vector3.UP).normalized()

	# Calculate desired velocity from input.
	var wish_vel := Vector3.ZERO
	# W (forward) = climb up, S (back) = climb down.
	wish_vel += up_dir * (-input_dir.y) * climb_speed
	# A/D = shimmy sideways.
	wish_vel += shimmy_dir * input_dir.x * shimmy_speed

	# Pull toward anchor midpoint — so when you grab both hands you get drawn
	# close to your grips instead of floating in space.
	var midpoint := (left_anchor + right_anchor) * 0.5
	var to_mid := midpoint - global_position
	var mid_dist := to_mid.length()
	if mid_dist > 0.5:
		wish_vel += to_mid.normalized() * pull_to_anchors_strength

	# Apply movement.
	var new_pos := global_position + wish_vel * delta

	# CONSTRAINT: body can't be farther than max_reach from either anchor.
	new_pos = _constrain_to_anchors(new_pos)

	global_position = new_pos
	velocity = wish_vel

	# Space = push off (manual mantle). Releases both hands and launches you
	# up + forward toward where you're looking. If you grabbed a ledge, this
	# should carry you up and over onto the platform — IF you aimed right.
	# No auto-teleport, no raycast. Pure physics. You earn the mantle.
	if Input.is_action_just_pressed("jump"):
		if stamina >= stamina_drain_launch:
			# Forward = horizontal direction from player toward anchors.
			var forward := Vector3(to_mid.x, 0, to_mid.z).normalized()
			if forward.length_squared() < 0.01:
				forward = -camera.global_transform.basis.z
				forward.y = 0
				forward = forward.normalized()
			velocity = Vector3.UP * push_off_up + forward * push_off_forward
			stamina -= stamina_drain_launch
			_release_hand(true)
			_release_hand(false)
			swing_vel = Vector3.ZERO


func _constrain_to_anchors(pos: Vector3) -> Vector3:
	## Pull pos back within max_reach of both anchor points.
	var constrained := pos
	var anchors: Array[Vector3] = [left_anchor, right_anchor]
	for anchor in anchors:
		var offset: Vector3 = constrained - anchor
		var dist := offset.length()
		if dist > max_reach:
			constrained = anchor + offset.normalized() * max_reach
	return constrained


# ─── Stamina ─────────────────────────────────────────────────────────────────

func _process_stamina(delta: float) -> void:
	var anchored := _anchored_count()
	if anchored == 0:
		var rate := stamina_regen if is_on_floor() else stamina_regen * 0.3
		stamina = minf(stamina + rate * delta, max_stamina)
	elif anchored == 1:
		stamina -= stamina_drain_one_hand * delta
	elif anchored == 2:
		stamina -= stamina_drain_two_hands * delta

	if stamina <= 0.0:
		stamina = 0.0
		_release_hand(true)
		_release_hand(false)
		swing_vel = velocity


## Called by the tether to apply rope tension this frame.
func apply_tether_force(force: Vector3) -> void:
	external_force += force


## Debug info for HUD.
func get_climb_state() -> String:
	var c := _anchored_count()
	if c == 0:
		return "FREE"
	elif c == 1:
		return "SWING"
	elif c == 2:
		return "CLIMB"
	return "?"