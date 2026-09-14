class_name PlayerOverlay
extends MeshInstance3D

signal action(name: String)
signal seek_requested(milliseconds: int)
var viewport: SubViewport
var title: Label
var timeline: PlaybackTimeline
var pause_button: Button
var panel_size := Vector2(3.4, 0.75)
var play_icon: Texture2D
var pause_icon: Texture2D

func _ready() -> void:
	play_icon = load("res://assets/icons/play.svg")
	pause_icon = load("res://assets/icons/pause.svg")
	viewport = SubViewport.new()
	viewport.size = Vector2i(1400, 300)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = viewport.get_texture()
	material_override = material
	var panel := PanelContainer.new()
	panel.theme = Widgets.theme()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", Widgets.surface(Color("101624db"), 22, 24))
	viewport.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	panel.add_child(body)
	title = Widgets.label("Now playing", body, 26)
	title.clip_text = true
	timeline = PlaybackTimeline.new()
	body.add_child(timeline)
	timeline.seek_requested.connect(func(value: int): seek_requested.emit(value))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	body.add_child(row)
	for entry in [["Pause", "pause"], ["Back 10 seconds", "back"], ["Forward 30 seconds", "forward"], ["Stop", "stop"], ["Settings", "settings"], ["Library", "library"], ["Hide controls", "hide"]]:
		var button := Widgets.button("", func(): action.emit(entry[1]), row)
		button.icon = load("res://assets/icons/%s.svg" % entry[1])
		button.tooltip_text = entry[0]
		button.accessibility_name = entry[0]
		button.custom_minimum_size = Vector2(140, 72)
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.add_theme_constant_override("icon_max_width", 44)
		if entry[1] == "pause": pause_button = button
	hide()

func fit_screen(width: float, aspect: float, curvature: float) -> void:
	panel_size = Vector2(width * 0.94, width * 0.94 * 300.0 / 1400.0)
	var quad := QuadMesh.new()
	quad.size = panel_size
	mesh = quad
	position.y = -width / aspect / 2.0 + panel_size.y / 2.0 + width * 0.02
	position.z = (1.0 - cos(curvature / 2.0)) * width / curvature + 0.025 if curvature > 0.001 else 0.025

func update_time(position_ms: int, duration_ms: int, ready: bool, paused: bool) -> void:
	timeline.update_time(position_ms, duration_ms, ready)
	pause_button.icon = play_icon if paused else pause_icon
	pause_button.tooltip_text = "Play" if paused else "Pause"
	pause_button.accessibility_name = pause_button.tooltip_text
