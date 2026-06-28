extends Node3D
## Tethered — the rising threat. A "darkness" kill-plane that creeps up from the
## bottom of the labyrinth, accelerating slowly. Touch it and the run fails.
## Visualized as a large translucent slab; later this becomes a fog/monster.

@export var base_speed: float = 0.4
@export var acceleration: float = 0.015
@export var catch_up_bonus: float = 0.6  ## Extra speed when far below players.

var _speed: float = 0.0
@onready var kill_area: Area3D = $KillArea


func _ready() -> void:
	_speed = base_speed
	GameManager.run_started.connect(_on_run_started)
	if kill_area:
		kill_area.body_entered.connect(_on_body_entered)


func _on_run_started() -> void:
	global_position.y = GameManager.threat_depth
	_speed = base_speed


func _physics_process(delta: float) -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return

	_speed += acceleration * delta

	# Rubber-band: if the lowest player has pulled far ahead, speed up a little
	# so the threat stays menacing without instantly catching slow players.
	var gap := GameManager.get_lowest_player_y() - global_position.y
	var rubber := clampf(gap / 30.0, 0.0, 1.0) * catch_up_bonus

	global_position.y += (_speed + rubber) * delta
	GameManager.set_threat_depth(global_position.y)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("players"):
		GameManager.fail_run("The dark caught up.")
