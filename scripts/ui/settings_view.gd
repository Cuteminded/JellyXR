class_name SettingsView
extends VBoxContainer

signal screen_changed
signal screen_follow_changed
signal environment_changed
signal stereo_selected(value: int)
signal projection_selected(value: int)
signal eyes_swapped
signal status(message: String)

var settings: JellyXRSettings
var stereo_mode := Stereo.Mode.MONO
var projection_mode := VideoProjection.Mode.SCREEN
var swap_eyes := false
var passthrough_supported := false
var sort_choices: GridContainer
var screen_dimensions: GridContainer
var stereo_choices: HFlowContainer
var reset_screen_button: Button
var playback_choices: VBoxContainer
var transcode_options: VBoxContainer
var transcode_choices: HFlowContainer
var sections: Array[VBoxContainer] = []
var scroll: ScrollContainer
var dragging_slider := false
var navigation_host: Container
var navigation: GridContainer
var navigation_buttons: Array[Button] = []
var section_heading: Label
var sort_order_choices: HBoxContainer
var environment_choices: VBoxContainer
var environment_buttons: Dictionary = {}
var follow_switch: CheckButton

const SECTION_TITLES := ["Library sorting", "Screen", "Environment", "Playback"]
const SECTION_ICONS := [
	preload("res://assets/icons/material/video_library.svg"),
	preload("res://assets/icons/material/tv.svg"),
	preload("res://assets/icons/material/home.svg"),
	preload("res://assets/icons/material/play_arrow.svg")
]

func _ready() -> void:
	add_theme_constant_override("separation", 20)
	_build_navigation()
	section_heading = Widgets.label(SECTION_TITLES[0], self, 28)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	for index in range(4):
		var section := VBoxContainer.new()
		section.add_theme_constant_override("separation", 24)
		section.visible = index == 0
		body.add_child(section)
		sections.append(section)
	_build_library(sections[0])
	_build_screen(sections[1])
	_build_environment(sections[2])
	_build_playback(sections[3])
	resized.connect(_adapt_columns)
	scroll.resized.connect(_adapt_columns)
	_adapt_columns()

func _build_navigation() -> void:
	navigation = GridContainer.new()
	navigation.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	navigation.add_theme_constant_override("v_separation", 8)
	navigation.add_theme_constant_override("h_separation", 8)
	navigation_host.add_child(navigation)
	var group := ButtonGroup.new()
	for index in range(4):
		var title: String = SECTION_TITLES[index]
		var button := Widgets.button(title, func(): _show_section(index), navigation)
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = index == 0
		button.accessibility_name = title
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.icon = SECTION_ICONS[index]
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 24)
		button.add_theme_constant_override("h_separation", 12)
		button.add_theme_font_size_override("font_size", 19)
		button.custom_minimum_size = Vector2(0, 64)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_control(button)
		navigation_buttons.append(button)

func _show_section(index: int) -> void:
	for section_index in range(sections.size()):
		sections[section_index].visible = section_index == index
	navigation_buttons[index].button_pressed = true
	section_heading.text = SECTION_TITLES[index]
	scroll.scroll_vertical = 0

func _card(parent: VBoxContainer, title: String = "") -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Widgets.surface(Color("162133"), 20, 20))
	parent.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	panel.add_child(body)
	if not title.is_empty(): Widgets.label(title, body, 22)
	return body

func _style_control(control: Button) -> void:
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var color := Color("202a3d")
		if state in ["hover", "disabled"]: color = Color("34435b")
		if state in ["pressed", "hover_pressed"]: color = Color("2b4b50")
		if state == "focus": color = Color(0, 0, 0, 0)
		var style := Widgets.surface(color, 12, 12)
		if state in ["hover", "hover_pressed", "focus"]:
			style.set_border_width_all(3)
			style.border_color = Color("6de3cf")
		control.add_theme_stylebox_override(state, style)
	control.add_theme_color_override("font_disabled_color", Color("8793a8"))

func _hint(message: String, parent: Node) -> void:
	var label := Widgets.label(message, parent, 18)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color("a4aec0"))

func _build_library(parent: VBoxContainer) -> void:
	_hint("Choose how to sort your libraries. Home shows the newest additions first.", parent)
	var order_card := _card(parent, "Sort order")
	sort_order_choices = HBoxContainer.new()
	sort_order_choices.add_theme_constant_override("separation", 12)
	order_card.add_child(sort_order_choices)
	var order_group := ButtonGroup.new()
	for value in ["Ascending", "Descending"]:
		_choice(value, value == settings.library_sort_order, order_group, sort_order_choices,
			func(): settings.library_sort_order = value; _save())
	_hint("Ascending sorts A to Z, lowest to highest, or oldest to newest. Descending reverses the order. This setting does not affect Random.", order_card)
	var sort_card := _card(parent, "Sort by")
	sort_choices = GridContainer.new()
	sort_choices.add_theme_constant_override("h_separation", 8)
	sort_choices.add_theme_constant_override("v_separation", 8)
	sort_card.add_child(sort_choices)
	var group := ButtonGroup.new()
	for option in JellyXRSettings.LIBRARY_SORT_OPTIONS:
		_choice(option[0], option[1] == settings.library_sort_by, group, sort_choices,
			func(): settings.library_sort_by = option[1]; _save())

func _build_playback(parent: VBoxContainer) -> void:
	parent = _card(parent, "Playback quality")
	_hint("Choose the video quality. Your choice applies to the next video you start.", parent)
	playback_choices = VBoxContainer.new()
	playback_choices.add_theme_constant_override("separation", 12)
	parent.add_child(playback_choices)
	var group := ButtonGroup.new()
	var conversion_hint := "Jellyfin converts the video to the resolution you choose below, up to 30 fps."
	for option in [
		["Automatic", "auto", "Play the original file when supported. Otherwise, Jellyfin converts it."],
		["Original full resolution", "original", "Play the original file without conversion. Your device must support its format."],
		["Transcoded", "transcoded", conversion_hint]
	]:
		var row := VBoxContainer.new()
		playback_choices.add_child(row)
		_choice(option[0], option[1] == settings.playback_mode, group, row,
			func(): _select_playback_mode(option[1]))
		_hint(option[2], row)
	_build_transcode_options(parent)

func _select_playback_mode(value: String) -> void:
	settings.playback_mode = value
	transcode_options.visible = value == "transcoded"
	_save()

func _build_transcode_options(parent: VBoxContainer) -> void:
	transcode_options = VBoxContainer.new()
	transcode_options.add_theme_constant_override("separation", 12)
	transcode_options.visible = settings.playback_mode == "transcoded"
	parent.add_child(transcode_options)
	Widgets.label("Transcoded resolution", transcode_options, 26)
	transcode_choices = HFlowContainer.new()
	transcode_choices.add_theme_constant_override("h_separation", 12)
	transcode_choices.add_theme_constant_override("v_separation", 12)
	transcode_options.add_child(transcode_choices)
	var group := ButtonGroup.new()
	for resolution in JellyXRSettings.TRANSCODE_PRESETS:
		var preset: Dictionary = JellyXRSettings.TRANSCODE_PRESETS[resolution]
		_choice(preset.label, settings.transcode_resolution == resolution, group, transcode_choices,
			func(): settings.transcode_resolution = resolution; _save())
	_hint("Choose a maximum resolution. Smaller videos keep their size. Higher resolutions need a faster connection and more server processing power.", transcode_options)

func _choice(title: String, selected: bool, group: ButtonGroup, parent: Node, action: Callable) -> CheckBox:
	var choice := CheckBox.new()
	choice.text = title
	choice.accessibility_name = title
	choice.button_group = group
	choice.button_pressed = selected
	choice.custom_minimum_size = Vector2(0, 56)
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choice.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_style_control(choice)
	choice.pressed.connect(action)
	parent.add_child(choice)
	return choice

func _build_screen(parent: VBoxContainer) -> void:
	_build_projection(parent)
	_build_video_format(parent)
	_build_screen_position(parent)

func _build_screen_position(parent: VBoxContainer) -> void:
	parent = _card(parent)
	var header := HFlowContainer.new()
	header.add_theme_constant_override("h_separation", 18)
	header.add_theme_constant_override("v_separation", 12)
	parent.add_child(header)
	Widgets.label("Screen position", header, 26).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_screen_button = Widgets.button("Reset to defaults", _reset_screen, header)
	reset_screen_button.tooltip_text = "Reset screen size and position. Keep your environment and video format."
	_hint(_screen_position_hint(), parent)
	screen_dimensions = GridContainer.new()
	screen_dimensions.columns = 2
	screen_dimensions.add_theme_constant_override("h_separation", 24)
	screen_dimensions.add_theme_constant_override("v_separation", 18)
	parent.add_child(screen_dimensions)
	for entry in [["Width", "width", 1.5, 7.0, " m"], ["Distance", "distance", 1.5, 8.0, " m"], ["Height", "height", -2.0, 2.0, " m"], ["Curvature", "curvature", 0.0, 1.2, ""]]:
		_slider(entry, screen_dimensions)

func _screen_position_hint() -> String:
	if projection_mode != VideoProjection.Mode.SCREEN:
		return "Screen position does not affect 180° or 360° video. Recenter to change your forward direction."
	if settings.is_theatre():
		return "Cinema and Theatre have fixed screens. Choose Void or Passthrough on the Environment page to adjust it."
	return "Set the screen size, distance, height and curve."

func _build_video_format(parent: VBoxContainer) -> void:
	parent = _card(parent, "Picture format")
	_hint("jellyXR detects the 3D format. Choose a different format if the picture looks wrong.", parent)
	stereo_choices = HFlowContainer.new()
	stereo_choices.add_theme_constant_override("h_separation", 12)
	parent.add_child(stereo_choices)
	var group := ButtonGroup.new()
	for entry in [["2D", Stereo.Mode.MONO], ["Half-SBS", Stereo.Mode.HALF_SBS], ["Full-SBS", Stereo.Mode.FULL_SBS], ["Top-bottom", Stereo.Mode.TOP_BOTTOM]]:
		_choice(entry[0], entry[1] == stereo_mode, group, stereo_choices, func(): stereo_mode = entry[1]; stereo_selected.emit(entry[1]))
	var swap := CheckButton.new()
	swap.text = "Swap left and right eyes"
	swap.accessibility_name = swap.text
	_style_control(swap)
	swap.custom_minimum_size.y = 56
	swap.button_pressed = swap_eyes
	swap.toggled.connect(func(enabled: bool): swap_eyes = enabled; eyes_swapped.emit())
	parent.add_child(swap)

func _build_projection(parent: VBoxContainer) -> void:
	parent = _card(parent, "Video projection")
	_hint("180° fills the view in front of you. 360° surrounds you. Both use equirectangular video and hide the environment during playback. Fisheye and cubemap layouts are not supported.", parent)
	var choices := HFlowContainer.new()
	choices.add_theme_constant_override("h_separation", 12)
	choices.add_theme_constant_override("v_separation", 12)
	parent.add_child(choices)
	var group := ButtonGroup.new()
	for entry in [["Screen", VideoProjection.Mode.SCREEN], ["180°", VideoProjection.Mode.EQUIRECTANGULAR_180], ["360°", VideoProjection.Mode.EQUIRECTANGULAR]]:
		_choice(entry[0], entry[1] == projection_mode, group, choices, func():
			projection_mode = entry[1]
			projection_selected.emit(entry[1])
			_rebuild_screen.call_deferred())

func _build_environment(parent: VBoxContainer) -> void:
	_hint("Choose a background for your screen.", parent)
	environment_choices = VBoxContainer.new()
	environment_choices.add_theme_constant_override("separation", 16)
	parent.add_child(environment_choices)
	var adjustable := _card(environment_choices, "Void & Passthrough")
	var fixed := _card(environment_choices, "Cinema & Theatre")
	var group := ButtonGroup.new()
	var descriptions := [
		"A dark background. Change the screen size and position in Screen settings.",
		"See your room around the screen. Change its size and position in Screen settings." if passthrough_supported else "This device does not support passthrough.",
		"A cinema with a fixed screen. Recenter to face it.",
		"A simpler cinema with a fixed screen. Recenter to face it."
	]
	var values := ["Void", "Passthrough", "Cinema", "Theatre"]
	for index in range(values.size()):
		var value: String = values[index]
		var card := adjustable if index < 2 else fixed
		var choice := _choice(value, value == settings.environment, group, card,
			func(): settings.environment = value; _rebuild_screen(); environment_changed.emit(); _save())
		environment_buttons[value] = choice
		_hint(descriptions[index], card)
		if value == "Passthrough" and not passthrough_supported:
			choice.disabled = true
			choice.tooltip_text = descriptions[index]
	_build_follow_switch(adjustable)

func _build_follow_switch(parent: VBoxContainer) -> void:
	var toggle := CheckButton.new()
	toggle.text = "Follow your movement"
	toggle.accessibility_name = toggle.text
	toggle.button_pressed = settings.follow_screen
	toggle.custom_minimum_size.y = 56
	_style_control(toggle)
	parent.add_child(toggle)
	follow_switch = toggle
	toggle.toggled.connect(func(enabled: bool):
		settings.follow_screen = enabled
		screen_follow_changed.emit()
		_save())
	_hint("The screen follows you as you move or turn. Applies to both Void and Passthrough. Does not affect 180° or 360° video.", parent)

func _reset_screen() -> void:
	settings.reset_screen()
	_rebuild_screen()
	if reset_screen_button.is_visible_in_tree(): reset_screen_button.grab_focus()
	screen_changed.emit()
	_save()

func _rebuild_screen() -> void:
	dragging_slider = false
	var section := sections[1]
	for child in section.get_children():
		section.remove_child(child)
		child.queue_free()
	_build_screen(section)
	_adapt_columns()

func _slider(entry: Array, parent: Node) -> void:
	var row := VBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	var labels := HBoxContainer.new()
	row.add_child(labels)
	var name_label := Widgets.label(entry[0], labels, 22)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value_label := Widgets.label("%.2f%s" % [settings.get(entry[1]), entry[4]], labels, 20)
	var slider := preload("res://scripts/ui/screen_position_slider.gd").new()
	slider.accessibility_name = entry[0]
	slider.custom_minimum_size.y = 48
	slider.min_value = entry[2]
	slider.max_value = entry[3]
	slider.step = 0.05
	slider.value = settings.get(entry[1])
	slider.editable = not settings.is_theatre() and projection_mode == VideoProjection.Mode.SCREEN
	row.add_child(slider)
	slider.value_changed.connect(func(value: float):
		settings.set(entry[1], value)
		value_label.text = "%.2f%s" % [value, entry[4]]
		screen_changed.emit()
		if not dragging_slider: _save())
	slider.drag_started.connect(func(): dragging_slider = true)
	slider.drag_ended.connect(func(_changed: bool): dragging_slider = false; _save())

func _save() -> void:
	status.emit("Settings saved." if settings.save() == OK else "Could not save settings. Check available storage and try again.")

func _adapt_columns() -> void:
	var content_width := scroll.size.x - 40
	if sort_choices != null:
		sort_choices.columns = 2 if content_width >= 540 else 1
	if screen_dimensions != null:
		screen_dimensions.columns = 2 if content_width >= 540 else 1
