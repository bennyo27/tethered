extends Node
## Tethered — global game state singleton (autoload).
## Tracks run state, the rising threat depth, and player roster for the prototype.
## Co-op networking is stubbed for now: prototype runs locally with N players.

signal run_started
signal run_failed(reason: String)
signal run_won
signal threat_depth_changed(depth: float)

enum State { MENU, PLAYING, DEAD, WON }

const SUMMIT_HEIGHT: float = 200.0  ## Y to reach to win the prototype.

var state: State = State.MENU
var players: Array[Node] = []
## World-space Y of the rising threat (the thing chasing from below).
var threat_depth: float = -50.0
var run_time: float = 0.0


func register_player(p: Node) -> void:
	if p not in players:
		players.append(p)


func unregister_player(p: Node) -> void:
	players.erase(p)


func start_run() -> void:
	state = State.PLAYING
	run_time = 0.0
	threat_depth = -50.0
	run_started.emit()


func set_threat_depth(depth: float) -> void:
	threat_depth = depth
	threat_depth_changed.emit(depth)


func fail_run(reason: String) -> void:
	if state != State.PLAYING:
		return
	state = State.DEAD
	run_failed.emit(reason)


func win_run() -> void:
	if state != State.PLAYING:
		return
	state = State.WON
	run_won.emit()


func _process(delta: float) -> void:
	if state == State.PLAYING:
		run_time += delta


## Lowest living player's Y. Used by the threat to know how close it is.
func get_lowest_player_y() -> float:
	var lowest := INF
	for p in players:
		if is_instance_valid(p):
			lowest = min(lowest, p.global_position.y)
	return lowest if lowest != INF else 0.0


func get_highest_player_y() -> float:
	var highest := -INF
	for p in players:
		if is_instance_valid(p):
			highest = max(highest, p.global_position.y)
	return highest if highest != -INF else 0.0
