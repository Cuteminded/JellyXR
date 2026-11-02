class_name PlayerQuickAccess
extends PanelContainer

signal closed

var volume_control: PlayerVolumeControl
var tracks_menu: PlayerTracksMenu
var screen_mode: PlayerScreenMode
var statistics_panel: VBoxContainer
var statistics_values: Dictionary = {}
var heading: Label
var audio_track_heading: Label

func _ready() -> void:
	theme = Widgets.theme()
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	offset_left = -496
	offset_right = -30
	offset_bottom = -168
	var surface := Widgets.surface(Color("101624db"), 22, 22)
	surface.set_border_width_all(1)
	surface.border_color = Color("3d4c63")
	surface.shadow_color = Color(0, 0, 0, 0.25)
	surface.shadow_size = 16
	add_theme_stylebox_override("panel", surface)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	add_child(body)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	body.add_child(header)
	heading = Widgets.label("", header, 26)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_build_statistics(body)
	screen_mode = PlayerScreenMode.new()
	body.add_child(screen_mode)
	volume_control = PlayerVolumeControl.new()
	body.add_child(volume_control)
	audio_track_heading = Widgets.label("Audio track", body, 20)
	tracks_menu = PlayerTracksMenu.new()
	body.add_child(tracks_menu)
	minimum_size_changed.connect(_fit_content)
	hide()

func _build_statistics(parent: Node) -> void:
	statistics_panel = VBoxContainer.new()
	statistics_panel.add_theme_constant_override("separation", 0)
	parent.add_child(statistics_panel)
	for key in ["Source video", "Playback", "Source codec", "Source bitrate", "Video decoder", "Player state", "Playback resolution", "Hardware decoding", "Read ahead", "Renderer / FPS", "Dropped frames"]:
		var divider := HSeparator.new()
		var line := StyleBoxLine.new()
		line.color = Color("3d4c63")
		line.thickness = 1
		divider.add_theme_stylebox_override("separator", line)
		statistics_panel.add_child(divider)
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 38
		row.add_theme_constant_override("separation", 12)
		statistics_panel.add_child(row)
		var label := Widgets.label(key, row, 17)
		label.add_theme_color_override("font_color", Color("a4aec0"))
		var value := Widgets.label("N/A", row, 17)
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		value.custom_minimum_size.x = 160
		value.clip_text = true
		statistics_values[key] = value

func show_menu(name: String) -> void:
	volume_control.visible = name == "audio"
	audio_track_heading.visible = name == "audio"
	tracks_menu.visible = name in ["audio", "subtitles"]
	screen_mode.visible = name == "screen_mode"
	statistics_panel.visible = name == "statistics"
	heading.text = {"audio": "Audio", "subtitles": "Subtitles", "screen_mode": "Screen mode", "statistics": "Statistics for nerds"}[name]
	show()
	if tracks_menu.visible:
		tracks_menu.kind = "Audio" if name == "audio" else "Subtitle"
		tracks_menu.maximum_height = 300.0 if name == "audio" else 420.0
		refresh_tracks()
	if screen_mode.visible: screen_mode.refresh()
	_fit_content.call_deferred()

func refresh_tracks() -> void:
	if not tracks_menu.is_visible_in_tree(): return
	tracks_menu.refresh()
	_fit_content.call_deferred()

func _fit_content() -> void:
	offset_top = offset_bottom - get_combined_minimum_size().y

func _unhandled_key_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed("ui_cancel"):
		closed.emit()
		get_viewport().set_input_as_handled()

static func style_button(button: Button, outlined := true) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var color := Color("202a3d") if state in ["normal", "disabled"] else Color("34435b")
		var box := Widgets.surface(color, 12, 14)
		if outlined and state == "pressed" and button.toggle_mode:
			box.set_border_width_all(2)
			box.border_color = Color("6de3cf")
		button.add_theme_stylebox_override(state, box)
	var focus := Widgets.surface(Color.TRANSPARENT if outlined else Color("34435b"), 12)
	if outlined:
		focus.set_border_width_all(3)
		focus.border_color = Color("6de3cf")
	button.add_theme_stylebox_override("focus", focus)

