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
var tooltip: Label
var hovered_control: Control
var video_controls: Array[Button] = []
var stop_button: Button
var controls_spacer: Control
var controls_row: HBoxContainer
var photo_mode := false
var previous_photo: Button
var next_photo: Button
var statistics_button: Button
var statistics_panel: VBoxContainer
var statistics_values: Dictionary = {}
var statistics_provider: Callable
var statistics_elapsed := 0.0
var screen_dimensions := Vector3(3.6, 16.0 / 9.0, 0.0)

func _ready() -> void:
	play_icon = load("res://assets/icons/material/play_arrow.svg")
	pause_icon = load("res://assets/icons/material/pause.svg")
	viewport = SubViewport.new()
	viewport.size = Vector2i(1400, 300)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = viewport.get_texture()
	VrOverlayMaterial.apply_depth(material)
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
	timeline.slider.tooltip_text = ""
	timeline.slider.accessibility_name = "Seek to a time"
	timeline.slider.mouse_entered.connect(_show_tooltip.bind(timeline.slider))
	timeline.slider.mouse_exited.connect(_hide_tooltip.bind(timeline.slider))
	timeline.slider.focus_entered.connect(_show_tooltip.bind(timeline.slider))
	timeline.slider.focus_exited.connect(_hide_tooltip.bind(timeline.slider))
	_build_controls(body)
	tooltip = Widgets.label("", body, 20)
	tooltip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip.custom_minimum_size.y = 28
	_build_statistics(body)
	visibility_changed.connect(func():
		if not is_visible_in_tree(): set_statistics_visible(false))
	hide()

func _build_controls(parent: Control) -> void:
	var row := HBoxContainer.new()
	controls_row = row
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	pause_button = _add_control("Pause", "pause", "pause", row)
	stop_button = _add_control("Stop", "stop", "stop", row)
	_add_control("Back 10 seconds", "back", "replay_10", row)
	_add_control("Forward 30 seconds", "forward", "forward_30", row)
	controls_spacer = row.add_spacer(false)
	_add_control("Audio and subtitles", "tracks", "subtitles", row)
	_add_control("Settings", "settings", "settings", row)
	_add_control("Hide controls", "hide", "visibility_off", row)
	previous_photo = _add_control("Previous photo", "previous_photo", "chevron_left", row)
	next_photo = _add_control("Next photo", "next_photo", "chevron_right", row)
	previous_photo.hide()
	next_photo.hide()
	statistics_button = _add_control("Statistics for nerds", "statistics", "statistics", row)
	statistics_button.toggle_mode = true
	statistics_button.pressed.connect(func(): set_statistics_visible(not statistics_panel.visible))
	video_controls.append(statistics_button)

func _build_statistics(parent: Control) -> void:
	statistics_panel = VBoxContainer.new()
	statistics_panel.add_theme_constant_override("separation", 8)
	parent.add_child(statistics_panel)
	var heading := HBoxContainer.new()
	statistics_panel.add_child(heading)
	Widgets.label("Statistics for nerds", heading, 26).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 12)
	statistics_panel.add_child(grid)
	for key in ["Source video", "Playback resolution", "Playback", "Source codec", "Source bitrate", "Renderer / app FPS", "Player state", "Video decoder", "Hardware decoding", "Dropped frames", "Read ahead"]:
		Widgets.label(key, grid, 20)
		var value := Widgets.label("N/A", grid, 20)
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value.custom_minimum_size.x = 210
		value.clip_text = true
		statistics_values[key] = value
	statistics_panel.hide()

func set_statistics_visible(enabled: bool) -> void:
	enabled = enabled and not photo_mode
	statistics_panel.visible = enabled
	statistics_button.set_pressed_no_signal(enabled)
	viewport.size = Vector2i(820, 210) if photo_mode else Vector2i(1400, 620 if enabled else 300)
	fit_screen(screen_dimensions.x, screen_dimensions.y, screen_dimensions.z)
	statistics_elapsed = 0.0
	if enabled: _refresh_statistics()

func _refresh_statistics() -> void:
	if not statistics_provider.is_valid(): return
	var values: Dictionary = statistics_provider.call()
	for key in statistics_values:
		statistics_values[key].text = str(values.get(key, "N/A"))

func _add_control(label: String, action_name: String, icon_name: String, parent: Control) -> Button:
	var button := Widgets.button("", func(): action.emit(action_name), parent)
	if action_name in ["pause", "back", "forward", "tracks"]: video_controls.append(button)
	button.icon = load("res://assets/icons/material/%s.svg" % icon_name)
	button.accessibility_name = label
	button.custom_minimum_size = Vector2(140, 72)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_constant_override("icon_max_width", 44)
	button.mouse_entered.connect(_show_tooltip.bind(button))
	button.mouse_exited.connect(_hide_tooltip.bind(button))
	button.focus_entered.connect(_show_tooltip.bind(button))
	button.focus_exited.connect(_hide_tooltip.bind(button))
	return button

func set_photo_mode(enabled: bool) -> void:
	photo_mode = enabled
	set_statistics_visible(false)
	previous_photo.visible = enabled
	next_photo.visible = enabled
	controls_row.move_child(previous_photo, 0 if enabled else controls_row.get_child_count() - 1)
	controls_row.move_child(next_photo, 1 if enabled else controls_row.get_child_count() - 1)
	timeline.visible = not enabled
	for button in video_controls: button.visible = not enabled
	controls_spacer.visible = not enabled
	controls_row.alignment = BoxContainer.ALIGNMENT_CENTER if enabled else BoxContainer.ALIGNMENT_BEGIN
	stop_button.icon = load("res://assets/icons/material/logout.svg" if enabled else "res://assets/icons/material/stop.svg")
	stop_button.accessibility_name = "Exit" if enabled else "Stop"
	viewport.size = Vector2i(820, 210) if enabled else Vector2i(1400, 300)
	fit_screen(screen_dimensions.x, screen_dimensions.y, screen_dimensions.z)
	hovered_control = null
	tooltip.text = ""

func set_photo_navigation(has_previous: bool, has_next: bool) -> void:
	previous_photo.disabled = not has_previous
	next_photo.disabled = not has_next

func _show_tooltip(control: Control) -> void:
	hovered_control = control
	tooltip.text = control.accessibility_name

func _hide_tooltip(control: Control) -> void:
	if hovered_control != control: return
	hovered_control = null
	tooltip.text = ""

func _process(_delta: float) -> void:
	if is_visible_in_tree() and statistics_panel.visible:
		statistics_elapsed += _delta
		if statistics_elapsed >= 1.0:
			statistics_elapsed = 0.0
			_refresh_statistics()
	if not is_visible_in_tree():
		hovered_control = null
		tooltip.text = ""
	elif is_instance_valid(hovered_control):
		tooltip.text = hovered_control.accessibility_name

func fit_screen(width: float, aspect: float, curvature: float) -> void:
	screen_dimensions = Vector3(width, aspect, curvature)
	var panel_width := width * 0.94 * float(viewport.size.x) / 1400.0
	panel_size = Vector2(panel_width, panel_width * float(viewport.size.y) / float(viewport.size.x))
	var quad := QuadMesh.new()
	quad.size = panel_size
	mesh = quad
	position.y = -width / aspect / 2.0 + panel_size.y / 2.0 + width * 0.02
	position.z = (1.0 - cos(curvature / 2.0)) * width / curvature + 0.025 if curvature > 0.001 else 0.025

func update_time(position_ms: int, duration_ms: int, ready: bool, paused: bool) -> void:
	timeline.update_time(position_ms, duration_ms, ready)
	pause_button.icon = play_icon if paused else pause_icon
	pause_button.accessibility_name = "Play" if paused else "Pause"
	if hovered_control == pause_button: tooltip.text = pause_button.accessibility_name
