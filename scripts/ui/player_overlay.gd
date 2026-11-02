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
var volume_control: PlayerVolumeControl
var controls_spacer: Control
var controls_row: HBoxContainer
var photo_mode := false
var previous_photo: Button
var next_photo: Button
var episode_label: Label
var bar: PanelContainer
var quick_access: PlayerQuickAccess
var submenu_buttons: Dictionary = {}
var active_menu := ""
var statistics_panel: VBoxContainer
var statistics_values: Dictionary = {}
var statistics_provider: Callable
var statistics_elapsed := 0.0
var screen_dimensions := Vector3(3.6, 16.0 / 9.0, 0.0)

func _ready() -> void:
	play_icon = load("res://assets/icons/material/play_arrow.svg")
	pause_icon = load("res://assets/icons/material/pause.svg")
	viewport = SubViewport.new()
	viewport.size = Vector2i(1400, 360)
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
	bar = panel
	panel.theme = Widgets.theme()
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_top = -360
	panel.add_theme_stylebox_override("panel", Widgets.surface(Color("101624db"), 22, 30))
	viewport.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	panel.add_child(body)
	episode_label = Widgets.label("", body, 16)
	episode_label.add_theme_color_override("font_color", Color("a4aec0"))
	episode_label.hide()
	title = Widgets.label("Now playing", body, 36)
	title.clip_text = true
	timeline = PlaybackTimeline.new()
	body.add_child(timeline)
	timeline.seek_requested.connect(func(value: int): seek_requested.emit(value))
	timeline.slider.tooltip_text = ""
	timeline.slider.accessibility_name = "Seek to a time"
	_build_controls(body)
	tooltip = Widgets.label("", viewport, 20)
	tooltip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip.add_theme_stylebox_override("normal", Widgets.surface(Color("101624"), 8, 8))
	tooltip.hide()
	_build_statistics(viewport)
	bar.minimum_size_changed.connect(func(): _resize_viewport(quick_access.visible))
	_resize_viewport(false)
	visibility_changed.connect(func():
		if not is_visible_in_tree(): close_menu())
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
	_add_control("Library", "library", "video_library", row)
	for entry in [["Volume", "volume", "volume_up"], ["Subtitles", "subtitles", "subtitles"], ["Audio track", "audio", "audio_track"], ["Screen mode", "screen_mode", "tv"], ["Statistics for nerds", "statistics", "statistics"]]:
		var button := _add_control(entry[0], entry[1], entry[2], row)
		button.toggle_mode = true
		PlayerQuickAccess.style_button(button, false)
		button.pressed.connect(func(): toggle_menu(entry[1]))
		submenu_buttons[entry[1]] = button
		video_controls.append(button)
	_add_control("Settings", "settings", "settings", row)
	previous_photo = _add_control("Previous photo", "previous_photo", "chevron_left", row)
	next_photo = _add_control("Next photo", "next_photo", "chevron_right", row)
	previous_photo.hide()
	next_photo.hide()

func _build_statistics(parent: Node) -> void:
	quick_access = PlayerQuickAccess.new()
	parent.add_child(quick_access)
	volume_control = quick_access.volume_control
	volume_control.mute_button.mouse_entered.connect(_show_tooltip.bind(volume_control.mute_button))
	volume_control.mute_button.mouse_exited.connect(_hide_tooltip.bind(volume_control.mute_button))
	volume_control.mute_button.focus_entered.connect(_show_tooltip.bind(volume_control.mute_button))
	volume_control.mute_button.focus_exited.connect(_hide_tooltip.bind(volume_control.mute_button))
	quick_access.closed.connect(close_menu)
	statistics_panel = quick_access.statistics_panel
	statistics_values = quick_access.statistics_values

func toggle_menu(name: String) -> void:
	if quick_access.visible and active_menu == name: close_menu()
	else: show_menu(name)

func show_menu(name: String) -> void:
	if photo_mode: return
	active_menu = name
	_resize_viewport(true)
	quick_access.show_menu(name)
	for key in submenu_buttons: submenu_buttons[key].set_pressed_no_signal(key == name)
	if name == "statistics":
		statistics_elapsed = 0.0
		_refresh_statistics()

func close_menu() -> void:
	var previous := active_menu
	active_menu = ""
	quick_access.hide()
	statistics_panel.hide()
	for button in submenu_buttons.values(): button.set_pressed_no_signal(false)
	_resize_viewport(false)
	if is_visible_in_tree() and not photo_mode and submenu_buttons.has(previous): submenu_buttons[previous].grab_focus()

func set_statistics_visible(enabled: bool) -> void:
	if enabled: show_menu("statistics")
	else: close_menu()

func _resize_viewport(expanded: bool) -> void:
	var bar_height := ceili(bar.get_combined_minimum_size().y)
	viewport.size = Vector2i(820, bar_height) if photo_mode else Vector2i(1400, 840 if expanded else bar_height)
	bar.offset_top = -bar_height
	fit_screen(screen_dimensions.x, screen_dimensions.y, screen_dimensions.z)

func set_media(item: Dictionary) -> void:
	title.text = str(item.get("Name", "Now playing"))
	episode_label.visible = not photo_mode and item.get("Type", "") == "Episode"
	if episode_label.visible:
		episode_label.text = "S%02d  E%02d" % [int(item.get("ParentIndexNumber", 0)), int(item.get("IndexNumber", 0))]

func _refresh_statistics() -> void:
	if not statistics_provider.is_valid(): return
	var values: Dictionary = statistics_provider.call()
	for key in statistics_values:
		statistics_values[key].text = str(values.get(key, "N/A"))

func _add_control(label: String, action_name: String, icon_name: String, parent: Control) -> Button:
	var button := Widgets.button("", func():
		if action_name not in ["volume", "audio", "subtitles", "screen_mode", "statistics"]: action.emit(action_name), parent)
	if action_name in ["pause", "back", "forward", "tracks"]: video_controls.append(button)
	button.icon = load("res://assets/icons/material/%s.svg" % icon_name)
	button.accessibility_name = label
	button.custom_minimum_size = Vector2(68, 68)
	PlayerQuickAccess.style_button(button, false)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_constant_override("icon_max_width", 34)
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
	volume_control.visible = not enabled
	timeline.visible = not enabled
	for button in video_controls: button.visible = not enabled
	controls_spacer.visible = not enabled
	controls_row.alignment = BoxContainer.ALIGNMENT_CENTER if enabled else BoxContainer.ALIGNMENT_BEGIN
	stop_button.icon = load("res://assets/icons/material/logout.svg" if enabled else "res://assets/icons/material/stop.svg")
	stop_button.accessibility_name = "Exit" if enabled else "Stop"
	_resize_viewport(false)
	fit_screen(screen_dimensions.x, screen_dimensions.y, screen_dimensions.z)
	hovered_control = null
	tooltip.text = ""
	tooltip.hide()

func set_photo_navigation(has_previous: bool, has_next: bool) -> void:
	previous_photo.disabled = not has_previous
	next_photo.disabled = not has_next

func _show_tooltip(control: Control) -> void:
	hovered_control = control
	tooltip.text = control.accessibility_name
	tooltip.show()
	_position_tooltip()

func _hide_tooltip(control: Control) -> void:
	if hovered_control != control: return
	hovered_control = null
	tooltip.text = ""
	tooltip.hide()

func _process(_delta: float) -> void:
	if is_visible_in_tree() and quick_access.visible and statistics_panel.visible:
		statistics_elapsed += _delta
		if statistics_elapsed >= 1.0:
			statistics_elapsed = 0.0
			_refresh_statistics()
	if not is_visible_in_tree():
		hovered_control = null
		tooltip.text = ""
		tooltip.hide()
	elif is_instance_valid(hovered_control):
		tooltip.text = hovered_control.accessibility_name
		_position_tooltip()

func _position_tooltip() -> void:
	if not is_instance_valid(hovered_control): return
	tooltip.reset_size()
	var target := hovered_control.get_global_rect()
	tooltip.position = Vector2(clampf(target.get_center().x - tooltip.size.x / 2.0, 8, viewport.size.x - tooltip.size.x - 8), target.position.y - tooltip.size.y - 8)

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
