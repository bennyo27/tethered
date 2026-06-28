extends CanvasLayer
## Tethered — minimal prototype HUD: height, threat gap, stamina, climb state, banner.
## Also handles the tether toggle (T key) for solo testing.

@onready var height_label: Label = $Margin/VBox/Height
@onready var gap_label: Label = $Margin/VBox/Gap
@onready var stamina_label: Label = $Margin/VBox/Stamina
@onready var state_label: Label = $Margin/VBox/State
@onready var banner: Label = $Center/Banner

var tether_enabled: bool = true
var n_tether: Node3D = null
var n_player2: Node3D = null
var _banner_timer: float = 0.0


func _ready() -> void:
	banner.text = ""
	GameManager.run_failed.connect(_on_failed)
	GameManager.run_won.connect(_on_won)
	GameManager.start_run()
	# Find tether and player2 nodes from the scene tree.
	var root := get_tree().current_scene
	n_tether = root.get_node_or_null("Tether")
	n_player2 = root.get_node_or_null("Player2")


func _process(delta: float) -> void:
	# Toggle tether + player2 on/off for solo testing.
	if Input.is_action_just_pressed("toggle_tether"):
		_toggle_tether()

	# Banner auto-clear timer.
	if _banner_timer > 0.0:
		_banner_timer -= delta
		if _banner_timer <= 0.0:
			# Only clear if it was a toggle banner (not game-over/win).
			if GameManager.state == GameManager.State.PLAYING:
				banner.text = ""

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
			if p.stamina < 20.0:
				stamina_label.modulate = Color(1, 0.3, 0.3)
			else:
				stamina_label.modulate = Color(1, 1, 1)

	if GameManager.state == GameManager.State.PLAYING and h >= GameManager.SUMMIT_HEIGHT:
		GameManager.win_run()
	if Input.is_action_just_pressed("restart"):
		get_tree().reload_current_scene()


func _toggle_tether() -> void:
	tether_enabled = not tether_enabled
	if n_tether:
		n_tether.set_physics_process(tether_enabled)
		# Hide rope visuals.
		for child in n_tether.get_children():
			if child is MeshInstance3D:
				child.visible = tether_enabled
	if n_player2:
		n_player2.visible = tether_enabled
		# Disable player2's collision when hidden.
		var col := n_player2.get_node_or_null("Collision") as CollisionShape3D
		if col:
			col.disabled = not tether_enabled
		# Unregister from GameManager so it doesn't affect lowest/highest player.
		if tether_enabled:
			GameManager.register_player(n_player2)
		else:
			GameManager.unregister_player(n_player2)
	# Show toggle status as banner flash.
	if tether_enabled:
		_show_banner("Tether ON — 2 players", Color(0.4, 1, 0.5), 1.5)
	else:
		_show_banner("Tether OFF — solo test", Color(0.5, 0.7, 1), 1.5)


func _show_banner(text: String, color: Color, duration: float) -> void:
	banner.text = text
	banner.modulate = color
	_banner_timer = duration


func _on_failed(reason: String) -> void:
	banner.text = "%s\nPress R to restart." % reason
	banner.modulate = Color(1, 0.3, 0.3)
	_banner_timer = 0.0  # don't auto-clear game-over


func _on_won() -> void:
	banner.text = "You reached the summit. Together.\nPress R to restart."
	banner.modulate = Color(0.4, 1, 0.5)
	_banner_timer = 0.0  # don't auto-clear win