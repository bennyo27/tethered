extends Node3D
## Tethered — the Hunter. Currently a stub state machine that lives just above
## the rising threat and will eventually break off to actively pursue players
## through the labyrinth gaps. For the prototype it simply tracks the threat
## depth so the design hooks are in place.

enum AIState { DORMANT, RISING, HUNTING }

@export var rise_offset: float = -3.0  ## How far below the threat plane it sits.

var state: AIState = AIState.DORMANT


func _ready() -> void:
	GameManager.run_started.connect(func(): state = AIState.RISING)


func _physics_process(_delta: float) -> void:
	match state:
		AIState.DORMANT:
			pass
		AIState.RISING:
			global_position.y = GameManager.threat_depth + rise_offset
			# TODO: when a player is isolated/slow, transition to HUNTING and
			# pathfind up through the nearest gap.
		AIState.HUNTING:
			# TODO: chase nearest player; climb through gaps; grab + drag down.
			pass
