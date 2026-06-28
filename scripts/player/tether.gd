extends Node3D
## Tethered — the rope binding two players together.
## Verlet-integrated rope for visuals + a hard distance constraint that pulls
## the players toward each other when the rope goes taut. This is the heart of
## the friendslop: one player falling yanks the other.

@export var player_a_path: NodePath
@export var player_b_path: NodePath
@export var max_length: float = 8.0
@export var pull_strength: float = 25.0
@export var segment_count: int = 16
@export var rope_color: Color = Color(0.15, 0.12, 0.1)

var _a: Node3D
var _b: Node3D
var _points: PackedVector3Array
var _prev_points: PackedVector3Array
var _draw: MeshInstance3D
var _imm: ImmediateMesh


func _ready() -> void:
	_a = get_node_or_null(player_a_path)
	_b = get_node_or_null(player_b_path)
	if _a == null or _b == null:
		push_warning("Tether: both player paths must be set.")
		set_physics_process(false)
		return

	_points.resize(segment_count)
	_prev_points.resize(segment_count)
	for i in segment_count:
		var t := float(i) / float(segment_count - 1)
		var p: Vector3 = _a.global_position.lerp(_b.global_position, t)
		_points[i] = p
		_prev_points[i] = p

	_imm = ImmediateMesh.new()
	_draw = MeshInstance3D.new()
	_draw.mesh = _imm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = rope_color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_draw.material_override = mat
	add_child(_draw)


func _physics_process(delta: float) -> void:
	_apply_constraint(delta)
	_simulate_rope(delta)
	_redraw()


## Hard distance constraint: if players are farther apart than max_length,
## pull them together. Falling teammate => sideways/downward yank.
func _apply_constraint(delta: float) -> void:
	var ab: Vector3 = _b.global_position - _a.global_position
	var dist := ab.length()
	if dist <= max_length or dist < 0.001:
		return

	var dir := ab / dist
	var excess := dist - max_length
	var force := dir * excess * pull_strength

	if _a.has_method("apply_tether_force"):
		_a.apply_tether_force(force)
	if _b.has_method("apply_tether_force"):
		_b.apply_tether_force(-force)


func _simulate_rope(delta: float) -> void:
	var gravity := Vector3(0, -9.8, 0)
	# Pin endpoints to the players.
	_points[0] = _a.global_position
	_points[segment_count - 1] = _b.global_position

	# Verlet integrate the middle points.
	for i in range(1, segment_count - 1):
		var temp := _points[i]
		var vel := (_points[i] - _prev_points[i])
		_points[i] += vel + gravity * delta * delta
		_prev_points[i] = temp

	# Relax distance constraints between segments a few iterations.
	var seg_len := max_length / float(segment_count - 1)
	for _iter in 5:
		for i in range(segment_count - 1):
			var p1 := _points[i]
			var p2 := _points[i + 1]
			var d := p2 - p1
			var dl := d.length()
			if dl < 0.0001:
				continue
			var diff := (dl - seg_len) / dl
			var corr := d * 0.5 * diff
			if i != 0:
				_points[i] += corr
			if i + 1 != segment_count - 1:
				_points[i + 1] -= corr


func _redraw() -> void:
	_imm.clear_surfaces()
	_imm.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in _points:
		_imm.surface_add_vertex(to_local(p))
	_imm.surface_end()
