extends CanvasLayer
## Tethered — minimal prototype HUD: height, threat gap, stamina, climb state, banner.

@onready var height_label: Label = $Margin/VBox/Height
@onready var gap_label: Label = $Margin/VBox/Gap
@onready var stamina_label: Label = $Margin/VBox/Stamina
@onready var state_label: Label = $Margin/VBox/State
@onready var banner: Label = $Center/Banner


func _ready() -> void:
	banner.text = ""
	GameManager.run_failed.connect(_on_failed)
	GameManager.run_won.connect(_on_won)
	GameManager.start_run()


func _process(_delta: float) -> void:
	var h := GameManager.get_highest_player_y()
	var gap := GameManager.get_lowest_player_y() - GameManager.threat_depth
	height_label.text = "Height: %.1f m / %.0f" % [h, GameManager.SUMMIT_HEIGHT]
	gap_label.text = "Dark gap: %.1f m" % gap

	# Player1 stamina + climb state.
	if GameManager.players.size() > 0 and is_instance_valid(GameManager.players[0]):
		var p := GameManager.players[0]
		if p.has_method("get_climb_state"):
			state_label.text = "Climb: %s" % p.get_climb_state()
		if "stamina" in p:
			stamina_label.text = "Stamina: %.0f" % p.stamina
			# Red when low.
			if p.stamina < 20.0:
				stamina_label.modulate = Color(1, 0.3, 0.3)
			else:
				stamina_label.modulate = Color(1, 1, 1)

	if GameManager.state == GameManager.State.PLAYING and h >= GameManager.SUMMIT_HEIGHT:
		GameManager.win_run()
	if Input.is_action_just_pressed("restart"):
		get_tree().reload_current_scene()


func _on_failed(reason: String) -> void:
	banner.text = "%s\nPress R to restart." % reason
	banner.modulate = Color(1, 0.3, 0.3)


func _on_won() -> void:
	banner.text = "You reached the summit. Together.\nPress R to restart."
	banner.modulate = Color(0.4, 1, 0.5)
