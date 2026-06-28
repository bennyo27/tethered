extends Node3D
## Tethered — procedural vertical labyrinth generator (graybox).
## Builds a stack of vertical "chunks." Each chunk has a floor with a gap to
## climb through, perimeter walls, and a few climbable ledges. Seeded so co-op
## clients can later share a layout.

@export var chunk_count: int = 30
@export var chunk_height: float = 8.0
@export var chunk_size: float = 16.0
@export var wall_thickness: float = 0.5
@export var seed_value: int = 0

var _rng := RandomNumberGenerator.new()
var _mat_floor: StandardMaterial3D
var _mat_wall: StandardMaterial3D
var _mat_ledge: StandardMaterial3D


func _ready() -> void:
	if seed_value == 0:
		seed_value = randi()
	_rng.seed = seed_value
	_make_materials()
	generate()


func _make_materials() -> void:
	_mat_floor = StandardMaterial3D.new()
	_mat_floor.albedo_color = Color(0.3, 0.3, 0.32)
	_mat_wall = StandardMaterial3D.new()
	_mat_wall.albedo_color = Color(0.22, 0.22, 0.25)
	_mat_ledge = StandardMaterial3D.new()
	_mat_ledge.albedo_color = Color(0.45, 0.35, 0.2)


func generate() -> void:
	for c in get_children():
		c.queue_free()
	_spawn_base()
	for i in chunk_count:
		_spawn_chunk(i)


func _spawn_base() -> void:
	# Solid floor at y=0 so players don't fall into the void before climbing.
	var half := chunk_size * 0.5
	_add_box(Vector3(0, -0.5, 0), Vector3(chunk_size, 1.0, chunk_size), _mat_floor, "Base")
	# Low walls around the base perimeter as a backstop (so you don't walk off).
	_add_box(Vector3(0, 1.0, -half), Vector3(chunk_size, 2.0, wall_thickness), _mat_wall, "BaseWall")
	_add_box(Vector3(0, 1.0, half), Vector3(chunk_size, 2.0, wall_thickness), _mat_wall, "BaseWall")
	_add_box(Vector3(-half, 1.0, 0), Vector3(wall_thickness, 2.0, chunk_size), _mat_wall, "BaseWall")
	_add_box(Vector3(half, 1.0, 0), Vector3(wall_thickness, 2.0, chunk_size), _mat_wall, "BaseWall")


func _spawn_chunk(index: int) -> void:
	var y := index * chunk_height
	var half := chunk_size * 0.5

	# Perimeter walls (4).
	var wall_specs := [
		[Vector3(0, y + chunk_height * 0.5, -half), Vector3(chunk_size, chunk_height, wall_thickness)],
		[Vector3(0, y + chunk_height * 0.5, half), Vector3(chunk_size, chunk_height, wall_thickness)],
		[Vector3(-half, y + chunk_height * 0.5, 0), Vector3(wall_thickness, chunk_height, chunk_size)],
		[Vector3(half, y + chunk_height * 0.5, 0), Vector3(wall_thickness, chunk_height, chunk_size)],
	]
	for spec in wall_specs:
		_add_box(spec[0], spec[1], _mat_wall, "Wall")

	# Floor with a climb-gap (skip the bottom chunk so players have ground).
	if index > 0:
		var gap_x := _rng.randf_range(-half * 0.5, half * 0.5)
		var gap_z := _rng.randf_range(-half * 0.5, half * 0.5)
		var gap_size := _rng.randf_range(2.5, 4.0)
		# Build floor as 4 slabs around the gap.
		_add_floor_with_gap(y, half, gap_x, gap_z, gap_size)

	# A few climbable ledges scattered on the walls.
	var ledge_count := _rng.randi_range(3, 6)
	for l in ledge_count:
		var pos := Vector3(
			_rng.randf_range(-half * 0.8, half * 0.8),
			y + _rng.randf_range(1.0, chunk_height - 1.0),
			_rng.randf_range(-half * 0.8, half * 0.8)
		)
		var size := Vector3(_rng.randf_range(1.5, 3.0), 0.4, _rng.randf_range(1.0, 2.0))
		_add_box(pos, size, _mat_ledge, "Ledge")


func _add_floor_with_gap(y: float, half: float, gx: float, gz: float, gsize: float) -> void:
	var hg := gsize * 0.5
	# Left slab
	_add_box(Vector3((-half + (gx - hg)) * 0.5, y, 0),
		Vector3(absf((gx - hg) - (-half)), wall_thickness, chunk_size), _mat_floor, "Floor")
	# Right slab
	_add_box(Vector3((half + (gx + hg)) * 0.5, y, 0),
		Vector3(absf(half - (gx + hg)), wall_thickness, chunk_size), _mat_floor, "Floor")
	# Front slab (in the gap column)
	_add_box(Vector3(gx, y, (half + (gz + hg)) * 0.5),
		Vector3(gsize, wall_thickness, absf(half - (gz + hg))), _mat_floor, "Floor")
	# Back slab (in the gap column)
	_add_box(Vector3(gx, y, (-half + (gz - hg)) * 0.5),
		Vector3(gsize, wall_thickness, absf((gz - hg) - (-half))), _mat_floor, "Floor")


func _add_box(pos: Vector3, size: Vector3, mat: StandardMaterial3D, label: String) -> void:
	var body := StaticBody3D.new()
	body.name = "%s_%d" % [label, get_child_count()]
	body.position = pos

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = mat
	body.add_child(mesh)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)

	add_child(body)
