extends CharacterBody3D
## Tethered — first-person climbing controller with White Knuckle-style climbing.
##
## Core verbs:
##   LMB (hold)  — grab with LEFT hand (ray from camera-left)
##   RMB (hold)  — grab with RIGHT hand (ray from camera-right)
##   Mouse       — look around / aim hands
##   WASD        — walk on ground / swing-direction while hanging / climb-up while both hands grab
##   Space       — jump (ground) / LAUNCH off swing (hanging) / mantle-up (both hands on ledge)
##   Shift (hold) — sprint on ground
##   E           — interact (stub)
##   R           — restart run (handled by HUD)
##
## Climbing model:
##   - Each hand fires its own raycast. A hand is either FREE or ANCHORED at a
##     world-space point.
##   - 0 hands anchored  → normal walking/falling.
##   - 1 hand anchored   → PENDULUM: you swing on a rope of length = distance
##                          to the anchor. WASD adds tangential force to pump
##                          the swing. Space launches you tangent to the swing
##                          with your built-up velocity.
##   - 2 hands anchored  → CLIMBING: you're held between two anchor points.
##                          W/S moves you along the line between them (up/down).
##                          A/D shimmies sideways (perpendicular, horizontal).
##                          Space mantles up toward the higher anchor.
##
## Stamina:
##   - Gripping drains stamina. 1 hand = slow drain, 2 hands = faster.
##   - Launching costs a burst. Running out while hanging = forced release.
##   - Regenerates when both hands free and on ground.
##   - Low stamina = grip is unreliable (visual + audio cue later).

@export var move_speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var air_control: float = 0.3
@export var jump_velocity: float = 6.0
@export var mouse_sensitivity: float = 0.0025
@export var gravity: float = 18.0

## Climbing / swing tuning.
@export var swing_gravity: float = 5.0
@export var swing_pump_force: float = 10.0
@export var launch_force: float = 1.0  ## multiplier on current velocity at launch
@export var launch_boost: float = 2.5  ## flat upward boost on launch
@export var climb_speed: float = 4.0
@export var shimmy_speed: float = 3.0
@export var mantle_force: float = 9.0
@export var max_reach: float = 3.0  ## how far a hand can grab

## Mantle tuning.
@export var mantle_duration: float = 0.4  ## seconds for the mantle animation
@export var mantle_reach: float = 2.5  ## how far up/forward to detect a ledge
@export var mantle_forward_dist: float = 1.2  ## how far forward to place player on ledge

## Stamina.
@export var max_stamina: float = 100.0
@export var stamina_drain_one_hand: float = 4.0
@export var stamina_drain_two_hands: float = 7.0
@export var stamina_drain_launch: float = 20.0
@export var stamina_regen: float = 15.0
@export var stamina_min_grip: float = 5.0  ## below this, forced release

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

## Mantle state.
enum MantleState { NONE, MANTLING }
var mantle_state: MantleState = MantleState.NONE
var mantle_start_pos: Vector3 = Vector3.ZERO
var mantle_end_pos: Vector3 = Vector3.ZERO
var mantle_timer: float = 0.0

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
	# Mantle animation takes over completely.
	if mantle_state == MantleState.MANTLING:
		_process_mantle(delta)
		velocity += external_force * delta
		external_force = Vector3.ZERO
		move_and_slide()
		return

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


# ─── Mantle ──────────────────────────────────────────────────────────────────

func _try_mantle() -> bool:
	## When both hands are anchored, check if there's a walkable surface
	## above+forward that we can pull ourselves onto. Returns true if mantle
	## started.
	var avg_anchor := (left_anchor + right_anchor) * 0.5

	# Forward direction (away from wall, toward the platform top).
	var to_anchors := (avg_anchor - global_position).normalized()
	var forward := Vector3(to_anchors.x, 0, to_anchors.z).normalized()
	if forward.length_squared() < 0.01:
		forward = -camera.global_transform.basis.z
		forward.y = 0
		forward = forward.normalized()

	# Raycast from above+slightly-forward of anchors, straight down, to find
	# the ledge surface. Probing past the wall face so we hit the platform top.
	var probe_start := avg_anchor + Vector3(0, 1.5, 0) + forward * 0.3
	var probe_end := avg_anchor + Vector3(0, -0.5, 0) + forward * 0.3
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		probe_start, probe_end, 0xFFFFFFFF, [self]
	)
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return false

	var ledge_top: Vector3 = result.position

	# End position: stand on the ledge surface hit point, nudged slightly
	# forward from the edge. Use the ledge point, NOT the anchor position —
	# anchors are on the wall face and overshoot thin platforms.
	var end_pos := Vector3(
		ledge_top.x + forward.x * 0.4,
		ledge_top.y + 0.1,
		ledge_top.z + forward.z * 0.4
	)

	# Safety: don't mantle downward.
	if end_pos.y < global_position.y:
		return false

	# Start the mantle.
	mantle_state = MantleState.MANTLING
	mantle_start_pos = global_position
	mantle_end_pos = end_pos
	mantle_timer = 0.0
	_release_hand(true)
	_release_hand(false)
	swing_vel = Vector3.ZERO
	velocity = Vector3.ZERO
	return true


func _process_mantle(delta: float) -> void:
	mantle_timer += delta
	var t := clampf(mantle_timer / mantle_duration, 0.0, 1.0)
	# Ease-in-out curve so the mantle feels physical.
	var eased := t * t * (3.0 - 2.0 * t)

	# Lerp position with a slight arc (up first, then forward).
	var arc_y := sin(t * PI) * 0.3  # small hump over the ledge edge
	var pos := mantle_start_pos.lerp(mantle_end_pos, eased)
	pos.y += arc_y
	global_position = pos

	if t >= 1.0:
		mantle_state = MantleState.NONE
		velocity = Vector3.ZERO


# ─── Hand management ─────────────────────────────────────────────────────────

func _update_hands() -> void:
	# Left hand: grab on press if ray hits, release on release.
	if Input.is_action_just_pressed("grab_left"):
		_try_grab_hand(true)
	if Input.is_action_just_released("grab_left"):
		_release_hand(true)

	# Right hand.
	if Input.is_action_just_pressed("grab_right"):
		_try_grab_hand(false)
	if Input.is_action_just_released("grab_right"):
		_release_hand(false)


func _try_grab_hand(is_left: bool) -> void:
	var ray := left_ray if is_left else right_ray
	if not ray.is_colliding():
		return
	if stamina < stamina_min_grip:
		return  # too exhausted to grip

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
	if Input.is_action_pressed("jump") and is_on_floor():
		# jump action is space — but we use it for launch in swing. on ground it's jump.
		pass
	# Jump is handled separately below to avoid double-trigger.

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

	# Pump force: WASD adds tangential force in the horizontal plane.
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var wish := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if wish.length_squared() > 0.01:
		# Project wish onto tangent plane (remove radial component).
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
		# Remove radial velocity component (rope can't stretch).
		var radial := to_new.normalized()
		swing_vel -= radial * swing_vel.dot(radial)

	global_position = new_pos
	velocity = swing_vel  # keep move_and_slide happy

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
	## Body is constrained: can't move beyond max_reach from either anchor.
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")

	# Direction from lower to higher anchor.
	var a := left_anchor
	var b := right_anchor
	var up_dir := (b - a).normalized() if b.y > a.y else (a - b).normalized()
	var horizontal := Vector3(up_dir.x, 0, up_dir.z).normalized()
	if horizontal.length_squared() < 0.01:
		horizontal = -camera.global_transform.basis.z
		horizontal.y = 0
		horizontal = horizontal.normalized()
	# Shimmy direction = perpendicular to up_dir, horizontal.
	var shimmy_dir := up_dir.cross(Vector3.UP).normalized()

	# Calculate desired velocity from input.
	var wish_vel := Vector3.ZERO
	# W (forward) = climb up, S (back) = climb down.
	wish_vel += up_dir * (-input_dir.y) * climb_speed
	# A/D = shimmy sideways.
	wish_vel += shimmy_dir * input_dir.x * shimmy_speed

	# Apply movement.
	var new_pos := global_position + wish_vel * delta

	# CONSTRAINT: body can't be farther than max_reach from either anchor.
	# This is the arm-length limit — you can't float away from your grips.
	new_pos = _constrain_to_anchors(new_pos)

	global_position = new_pos
	velocity = wish_vel  # for move_and_slide / external forces

	# Space = mantle onto the platform above (if there is one).
	if Input.is_action_just_pressed("jump"):
		_try_mantle()


func _constrain_to_anchors(pos: Vector3) -> Vector3:
	## Pull pos back within max_reach of both anchor points.
	## If both constraints conflict, find the closest valid point.
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
		# Regen when free (faster if on ground).
		var rate := stamina_regen if is_on_floor() else stamina_regen * 0.3
		stamina = minf(stamina + rate * delta, max_stamina)
	elif anchored == 1:
		stamina -= stamina_drain_one_hand * delta
	elif anchored == 2:
		stamina -= stamina_drain_two_hands * delta

	# Grip failure.
	if stamina <= 0.0:
		stamina = 0.0
		_release_hand(true)
		_release_hand(false)
		swing_vel = velocity  # carry momentum into the fall


## Called by the tether to apply rope tension this frame.
func apply_tether_force(force: Vector3) -> void:
	external_force += force


## Debug info for HUD.
func get_climb_state() -> String:
	if mantle_state == MantleState.MANTLING:
		return "MANTLE"
	var c := _anchored_count()
	if c == 0:
		return "FREE"
	elif c == 1:
		return "SWING"
	elif c == 2:
		return "CLIMB"
	return "?"
