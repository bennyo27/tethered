extends CharacterBody3D
## Tethered — first-person climbing controller (prototype graybox).
## Walk, jump, mouse-look, and a simple "grab" that anchors the player to a
## ledge/wall so they can hang. Tether force is applied externally by RopeJoint.

@export var move_speed: float = 5.0
@export var air_control: float = 0.3
@export var jump_velocity: float = 6.0
@export var mouse_sensitivity: float = 0.0025
@export var gravity: float = 18.0
@export var climb_speed: float = 3.0

## External force accumulator (the tether pushes/pulls us each frame).
var external_force: Vector3 = Vector3.ZERO
var is_grabbing: bool = false
var _grab_point: Vector3 = Vector3.ZERO

@onready var camera: Camera3D = $Camera3D
@onready var grab_ray: RayCast3D = $Camera3D/GrabRay


func _ready() -> void:
	GameManager.register_player(self)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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
	_handle_grab()

	if is_grabbing:
		_climb_movement(delta)
	else:
		_free_movement(delta)

	# Apply tether/external force then reset the accumulator.
	velocity += external_force * delta
	external_force = Vector3.ZERO

	move_and_slide()


func _handle_grab() -> void:
	if Input.is_action_pressed("grab") and grab_ray.is_colliding():
		is_grabbing = true
		_grab_point = grab_ray.get_collision_point()
	else:
		is_grabbing = false


func _free_movement(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	var control := 1.0 if is_on_floor() else air_control
	if direction:
		velocity.x = lerpf(velocity.x, direction.x * move_speed, control)
		velocity.z = lerpf(velocity.z, direction.z * move_speed, control)
	elif is_on_floor():
		velocity.x = move_toward(velocity.x, 0, move_speed)
		velocity.z = move_toward(velocity.z, 0, move_speed)

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity


func _climb_movement(delta: float) -> void:
	# While grabbing, gravity is negated and we climb along the wall.
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	velocity.y = -input_dir.y * climb_speed
	velocity.x = (transform.basis * Vector3(input_dir.x, 0, 0)).x * climb_speed
	velocity.z = (transform.basis * Vector3(input_dir.x, 0, 0)).z * climb_speed

	if Input.is_action_just_pressed("jump"):
		# Push off the wall.
		is_grabbing = false
		velocity += -camera.global_transform.basis.z * jump_velocity


## Called by the tether to apply rope tension this frame.
func apply_tether_force(force: Vector3) -> void:
	external_force += force
