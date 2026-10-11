class_name TheatreEnvironment
extends Node3D

const INTERIOR := "res://assets/theatre/cinema.res"
const VIEWER_POSITION := Vector3(-69.6159, 1.18, -27.60)
const SOURCE_SCREEN_CENTER := Vector3(-69.47193, 1.7916, -22.45828)
const SCREEN_SIZE := Vector2(4.06, 1.84)
const SCREEN_POSITION := Vector3(VIEWER_POSITION.x - SOURCE_SCREEN_CENTER.x,
	SOURCE_SCREEN_CENTER.y - VIEWER_POSITION.y, VIEWER_POSITION.z - SOURCE_SCREEN_CENTER.z + 0.012)
const FLOOR := -1.3 - VIEWER_POSITION.y

var interior: Node3D
var screen_frame: MeshInstance3D
var low_resolution: Cinema
var low_res := false

func build(use_low_res: bool = false) -> void:
	for child in get_children(): child.free()
	interior = null
	low_resolution = null
	low_res = use_low_res
	if low_res:
		low_resolution = Cinema.new()
		add_child(low_resolution)
		low_resolution.build()
		screen_frame = low_resolution.screen_frame
		return
	interior = load(INTERIOR).instantiate()
	add_child(interior)
	screen_frame = MeshInstance3D.new()
	screen_frame.name = "ScreenFrame"
	var finish := StandardMaterial3D.new()
	finish.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	finish.albedo_color = Color("06090e")
	finish.cull_mode = BaseMaterial3D.CULL_DISABLED
	screen_frame.material_override = finish
	screen_frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	screen_frame.mesh = Stereo.mesh(SCREEN_SIZE.x + 0.02, (SCREEN_SIZE.x + 0.02) / (SCREEN_SIZE.y + 0.02), 0.0)
	screen_frame.position = SCREEN_POSITION - Vector3(0, 0, 0.01)
	add_child(screen_frame)

func set_low_res(value: bool) -> void:
	if low_res != value: build(value)

func recenter(viewer: Transform3D) -> void:
	var forward := -viewer.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001: return
	global_transform = Transform3D(Basis.looking_at(forward.normalized(), Vector3.UP), viewer.origin)

func projection_transform() -> Transform3D:
	if low_res: return low_resolution.projection_transform()
	return global_transform * Transform3D(Basis.IDENTITY, SCREEN_POSITION)

func video_size(aspect_ratio: float) -> Vector2:
	if low_res: return low_resolution.video_size(aspect_ratio)
	var width := minf(SCREEN_SIZE.x, SCREEN_SIZE.y * aspect_ratio)
	return Vector2(width, width / aspect_ratio)
