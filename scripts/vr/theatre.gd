class_name TheatreEnvironment
extends Node3D

const FLOOR := -1.6
const ROOM_WIDTH := 18.0
const FRONT := -12.0
const BACK := 11.0
const SCREEN_SIZE := Vector2(11.4, 5.5)
const SCREEN_POSITION := Vector3(0, 1.3, FRONT + 0.7)

var screen_frame: MeshInstance3D
var front_floor: MeshInstance3D
var batches: Dictionary = {}
var finishes: Dictionary = {}

func build() -> void:
	finishes = {
		"wall": _finish(Color("151b25")),
		"panel": _finish(Color("202633")),
		"floor": _finish(Color("10151d")),
		"ceiling": _finish(Color("0a0e15")),
		"fabric": _finish(Color("35212b")),
		"cushion": _finish(Color("4a2d3a")),
		"metal": _finish(Color("11151d")),
		"curtain": _finish(Color("2c1b28")),
		"curtain_fold": _finish(Color("3a2433")),
		"light": _finish(Color("547c8c")),
		"frame": _finish(Color("06090e"))
	}
	finishes.frame.cull_mode = BaseMaterial3D.CULL_DISABLED
	_build_room()
	_build_seating()
	_build_wall_panels()
	_build_curtains()
	_flush_batches()
	screen_frame = MeshInstance3D.new()
	screen_frame.name = "ScreenFrame"
	screen_frame.material_override = finishes.frame
	screen_frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	screen_frame.mesh = Stereo.mesh(SCREEN_SIZE.x + 0.24, (SCREEN_SIZE.x + 0.24) / (SCREEN_SIZE.y + 0.24), 0.0)
	screen_frame.position = SCREEN_POSITION - Vector3(0, 0, 0.06)
	add_child(screen_frame)

func recenter(viewer: Transform3D) -> void:
	var forward := -viewer.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001: return
	global_transform = Transform3D(Basis.looking_at(forward.normalized(), Vector3.UP), viewer.origin)

func projection_transform() -> Transform3D:
	return global_transform * Transform3D(Basis.IDENTITY, SCREEN_POSITION)

func video_size(aspect_ratio: float) -> Vector2:
	var width := minf(SCREEN_SIZE.x, SCREEN_SIZE.y * aspect_ratio)
	return Vector2(width, width / aspect_ratio)

func _finish(color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	result.albedo_color = color
	return result

func _box(size: Vector3, position_value: Vector3, finish: String) -> void:
	var key := "%s:%s" % [finish, size]
	if not batches.has(key): batches[key] = {"size": size, "finish": finish, "transforms": []}
	batches[key].transforms.append(Transform3D(Basis.IDENTITY, position_value))

func _build_room() -> void:
	_box(Vector3(ROOM_WIDTH, 0.2, BACK), Vector3(0, FLOOR - 0.1, BACK * 0.5), "floor")
	_box(Vector3(ROOM_WIDTH, 0.2, BACK - FRONT), Vector3(0, 5.0, (FRONT + BACK) * 0.5), "ceiling")
	for side in [-1.0, 1.0]:
		_box(Vector3(0.25, 6.6, BACK - FRONT), Vector3(side * ROOM_WIDTH * 0.5, 1.7, (FRONT + BACK) * 0.5), "wall")
	for depth in [FRONT, BACK]:
		_box(Vector3(ROOM_WIDTH, 6.6, 0.25), Vector3(0, 1.7, depth), "wall")
	for depth in [-9.0, -4.0, 1.0, 6.0]:
		_box(Vector3(ROOM_WIDTH, 0.14, 0.25), Vector3(0, 4.85, depth), "panel")
	front_floor = MeshInstance3D.new()
	front_floor.name = "FrontFloor"
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(ROOM_WIDTH, 0.2, -FRONT)
	front_floor.mesh = floor_mesh
	front_floor.position = Vector3(0, FLOOR - 0.1, FRONT * 0.5)
	front_floor.material_override = finishes.floor
	front_floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(front_floor)

func _build_seating() -> void:
	for row in range(5):
		var depth := 1.5 + row * 1.8
		var rise := row * 0.22
		_box(Vector3(15.6, 0.24 + rise, 1.8), Vector3(0, FLOOR + rise * 0.5 - 0.12, depth), "floor")
		for column in range(12):
			var x := (column - 5.5) * 1.05
			x += -0.5 if x < 0 else 0.5
			_seat(Vector3(x, FLOOR + rise, depth))
		for side in [-1.0, 1.0]:
			_box(Vector3(0.06, 0.025, 1.5), Vector3(side * 7.65, FLOOR + rise + 0.025, depth), "light")
	for side in [-1.0, 1.0]:
		for depth in [-1.0, -2.8]:
			_seat(Vector3(side * 6.4, FLOOR, depth))

func _seat(position_value: Vector3) -> void:
	_box(Vector3(0.62, 0.22, 0.64), position_value + Vector3(0, 0.46, 0), "fabric")
	_box(Vector3(0.58, 0.12, 0.57), position_value + Vector3(0, 0.61, -0.02), "cushion")
	_box(Vector3(0.64, 0.88, 0.2), position_value + Vector3(0, 0.88, 0.32), "fabric")
	_box(Vector3(0.56, 0.7, 0.06), position_value + Vector3(0, 0.9, 0.19), "cushion")
	_box(Vector3(0.16, 0.4, 0.26), position_value + Vector3(0, 0.2, 0), "metal")
	for side in [-1.0, 1.0]:
		_box(Vector3(0.12, 0.14, 0.64), position_value + Vector3(side * 0.39, 0.7, 0.02), "metal")

func _build_wall_panels() -> void:
	for side in [-1.0, 1.0]:
		for depth in [-9.0, -6.0, -3.0, 0.0, 3.0, 6.0, 9.0]:
			_box(Vector3(0.12, 3.4, 1.9), Vector3(side * 8.8, 1.1, depth), "panel")
			_box(Vector3(0.035, 0.06, 1.45), Vector3(side * 8.71, 2.2, depth), "light")
		_box(Vector3(0.045, 0.045, 20.0), Vector3(side * 8.72, FLOOR + 0.24, -0.5), "light")

func _build_curtains() -> void:
	for side in [-1.0, 1.0]:
		_box(Vector3(2.5, 5.8, 0.2), Vector3(side * 7.2, 1.35, FRONT + 0.3), "curtain")
		for fold in range(9):
			_box(Vector3(0.13, 5.8, 0.16), Vector3(side * 7.2 + (fold - 4) * 0.27, 1.35, FRONT + 0.46), "curtain_fold")
	_box(Vector3(ROOM_WIDTH - 0.4, 0.45, 0.3), Vector3(0, 4.5, FRONT + 0.3), "curtain")

func _flush_batches() -> void:
	for batch in batches.values():
		var mesh := BoxMesh.new()
		mesh.size = batch.size
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = mesh
		multimesh.instance_count = batch.transforms.size()
		for index in range(batch.transforms.size()):
			multimesh.set_instance_transform(index, batch.transforms[index])
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		instance.material_override = finishes[batch.finish]
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
	batches.clear()
