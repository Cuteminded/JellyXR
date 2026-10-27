class_name SubtitleOverlay
extends Label3D

var controls: PlayerOverlay
var preferred_y := 0.0
var controls_gap := 0.0

func _ready() -> void:
	no_depth_test = true
	outline_size = 10
	outline_modulate = Color.BLACK
	modulate = Color.WHITE
	shaded = false
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	width = 1250
	render_priority = 5

func fit_screen(dimensions: Vector3, settings: JellyXRSettings) -> void:
	font_size = settings.subtitle_size
	modulate = {"White": Color.WHITE, "Yellow": Color.YELLOW, "Green": Color.GREEN}.get(settings.subtitle_color, Color.WHITE)
	pixel_size = dimensions.x * 0.85 / 1250.0
	preferred_y = -dimensions.x / dimensions.y * (0.5 - settings.subtitle_height)
	controls_gap = dimensions.x * 0.025
	position.z = (1.0 - cos(dimensions.z / 2.0)) * dimensions.x / dimensions.z + 0.04 if dimensions.z > 0.001 else 0.04
	_update_position()

func _process(_delta: float) -> void:
	_update_position()

func _update_position() -> void:
	position.y = preferred_y
	if text.is_empty() or not is_instance_valid(controls) or not controls.is_visible_in_tree(): return
	var controls_top := controls.position.y + controls.panel_size.y / 2.0
	position.y = maxf(preferred_y, controls_top + controls_gap - get_aabb().position.y)
