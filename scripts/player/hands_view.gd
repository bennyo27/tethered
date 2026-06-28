extends Node3D
## Tethered — first-person hands view model (White Knuckle style).
## Two visible hands parented to the camera. Animate based on the player
## controller's hand states:
##   FREE     → hands lowered, relaxed, subtle sway from movement
##   ANCHORED → hands reach up toward the anchor point
## Smoothly lerps between poses. Also adds a subtle head-bob when walking.

@export var hand_reach_speed: float = 12.0
@export var sway_amount: float = 0.015
@export var bob_amount: float = 0.008
@export var bob_speed: float = 10.0

var _player: CharacterBody3D
var _left_hand: Node3D
var _right_hand: Node3D
var _left_rest: Transform3D
var _right_rest: Transform3D
var _bob_time: float = 0.0


func _ready() -> void:
	# Find the parent player controller.
	var p := get_parent()
	while p and not (p is CharacterBody3D):
		p = p.get_parent()
	_player = p as CharacterBody3D

	_left_hand = get_node_or_null("LeftHand")
	_right_hand = get_node_or_null("RightHand")
	if _left_hand:
		_left_rest = _left_hand.transform
	if _right_hand:
		_right_rest = _right_hand.transform


func _process(delta: float) -> void:
	if not _player or not _left_hand or not _right_hand:
		return

	_bob_time += delta

	# Base sway from velocity (horizontal).
	var vel := _player.velocity
	var speed := Vector2(vel.x, vel.z).length()
	var sway_x := sin(_bob_time * bob_speed * 0.5) * sway_amount * speed * 0.1
	var sway_y := absf(sin(_bob_time * bob_speed)) * bob_amount * speed * 0.1

	# Head bob when on ground and moving.
	var bob_z := 0.0
	if _player.is_on_floor() and speed > 0.5:
		bob_z = sin(_bob_time * bob_speed) * bob_amount

	# Animate each hand.
	_animate_hand(_left_hand, _left_rest, true, sway_x, sway_y, bob_z, delta)
	_animate_hand(_right_hand, _right_rest, false, sway_x, sway_y, bob_z, delta)


func _animate_hand(hand: Node3D, rest: Transform3D, is_left: bool,
		sway_x: float, sway_y: float, bob_z: float, delta: float) -> void:
	var anchored: bool = false
	var anchor: Vector3 = Vector3.ZERO
	var state_str: String = ""

	if _player.has_method("_anchored_count"):
		# Access the hand state directly.
		if is_left and "left_state" in _player:
			anchored = _player.left_state == _player.HandState.ANCHORED
			anchor = _player.left_anchor
		elif not is_left and "right_state" in _player:
			anchored = _player.right_state == _player.HandState.ANCHORED
			anchor = _player.right_anchor

	var target := rest

	if anchored:
		# Convert anchor world position to camera-local space.
		var cam := _player.get_node("Camera3D") as Camera3D
		if cam:
			var local_anchor := cam.to_local(anchor)
			# Hand reaches toward the anchor — offset to the hand's side.
			var side_offset := -0.3 if is_left else 0.3
			var basis := Basis.IDENTITY
			target = Transform3D(basis, Vector3(
				local_anchor.x + side_offset,
				clampf(local_anchor.y, -0.2, 0.8),
				local_anchor.z
			))
			# Rotate hand to "grip" — slight downward angle.
			target = target.rotated_local(Vector3.RIGHT, deg_to_rad(-15.0))
	else:
		# Rest pose + sway.
		target = rest
		target.origin.x += sway_x * (-1.0 if is_left else 1.0)
		target.origin.y += sway_y
		target.origin.z += bob_z

	# Smooth interpolation.
	var weight := clampf(hand_reach_speed * delta, 0.0, 1.0)
	hand.transform = hand.transform.interpolate_with(target, weight)
