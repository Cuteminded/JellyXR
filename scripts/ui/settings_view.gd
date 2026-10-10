class_name SettingsView
extends VBoxContainer

signal back_requested
signal screen_changed
signal stereo_selected(value: int)
signal eyes_swapped
signal status(message: String)

var settings: JellyframeSettings
var stereo_mode := Stereo.Mode.MONO
var swap_eyes := false
var sort_choices: GridContainer
var screen_dimensions: GridContainer
var sections: Array[VBoxContainer] = []
var scroll: ScrollContainer
var dragging_slider := false

func _ready() -> void:
	add_theme_constant_override("separation", 18)
	var navigation := HFlowContainer.new()
	navigation.add_theme_constant_override("h_separation", 12)
	navigation.add_theme_constant_override("v_separation", 12)
	add_child(navigation)
	var group := ButtonGroup.new()
	for index in range(2):
		var title: String = ["Library sorting", "Screen & environment"][index]
		var button := Widgets.button(title, func(): _show_section(index), navigation)
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = index == 0
		button.accessibility_name = title
		button.text = ("● " if index == 0 else "") + title
		button.toggled.connect(func(selected: bool): button.text = ("● " if selected else "") + title)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	for index in range(2):
		var section := VBoxContainer.new()
		section.add_theme_constant_override("separation", 18)
		section.visible = index == 0
		body.add_child(section)
		sections.append(section)
	_build_library(sections[0])
	_build_screen(sections[1])
	Widgets.button("Back", func(): back_requested.emit(), self)
	resized.connect(_adapt_columns)
	_adapt_columns()

func _show_section(index: int) -> void:
	for section_index in range(sections.size()):
		sections[section_index].visible = section_index == index
	scroll.scroll_vertical = 0

func _hint(message: String, parent: Node) -> void:
	var label := Widgets.label(message, parent, 18)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color("a4aec0"))

func _build_library(parent: VBoxContainer) -> void:
	_hint("Choose how titles are ordered in your libraries. Home stays sorted by date added, newest first. Changes are saved automatically.", parent)
	Widgets.label("Sort by", parent, 26)
	sort_choices = GridContainer.new()
	sort_choices.columns = 2
	sort_choices.add_theme_constant_override("h_separation", 18)
	sort_choices.add_theme_constant_override("v_separation", 8)
	parent.add_child(sort_choices)
	var group := ButtonGroup.new()
	for option in JellyframeSettings.LIBRARY_SORT_OPTIONS:
		_choice(option[0], option[1] == settings.library_sort_by, group, sort_choices,
			func(): settings.library_sort_by = option[1]; _save())
	var order_heading := Widgets.label("Sort order", parent, 26)
	var order := HBoxContainer.new()
	order.add_theme_constant_override("separation", 18)
	parent.add_child(order)
	var order_group := ButtonGroup.new()
	for value in ["Ascending", "Descending"]:
		_choice(value, value == settings.library_sort_order, order_group, order,
			func(): settings.library_sort_order = value; _save())
	parent.move_child(order_heading, 1)
	parent.move_child(order, 2)
	_hint("Ascending shows A to Z, lowest to highest, or oldest first. Descending reverses the order. Random ignores sort order.", parent)

func _choice(title: String, selected: bool, group: ButtonGroup, parent: Node, action: Callable) -> CheckBox:
	var choice := CheckBox.new()
	choice.text = title
	choice.accessibility_name = title
	choice.button_group = group
	choice.button_pressed = selected
	choice.custom_minimum_size = Vector2(0, 56)
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choice.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var style := Widgets.surface(Color("2b4b50") if state in ["pressed", "hover_pressed"] else Color("202a3d"), 12, 8)
		if state != "normal":
			style.set_border_width_all(2)
			style.border_color = Color("6de3cf")
		choice.add_theme_stylebox_override(state, style)
	choice.pressed.connect(action)
	parent.add_child(choice)
	return choice

func _build_screen(parent: VBoxContainer) -> void:
	var header := HFlowContainer.new()
	header.add_theme_constant_override("h_separation", 18)
	header.add_theme_constant_override("v_separation", 12)
	parent.add_child(header)
	Widgets.label("Screen position", header, 26).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var reset := Widgets.button("Reset to defaults", _reset_screen, header)
	reset.tooltip_text = "Restore screen size, distance, height, curvature and environment."
	_hint("Adjust your cinema screen. Position changes apply immediately and are saved automatically.", parent)
	screen_dimensions = GridContainer.new()
	screen_dimensions.columns = 2
	screen_dimensions.add_theme_constant_override("h_separation", 24)
	screen_dimensions.add_theme_constant_override("v_separation", 18)
	parent.add_child(screen_dimensions)
	for entry in [["Width", "width", 1.5, 7.0, " m"], ["Distance", "distance", 1.5, 8.0, " m"], ["Height", "height", -2.0, 2.0, " m"], ["Curvature", "curvature", 0.0, 1.2, ""]]:
		_slider(entry, screen_dimensions)
	Widgets.label("Video format", parent, 26)
	_hint("3D format is detected automatically. Override it here if the video looks wrong.", parent)
	var formats := HFlowContainer.new()
	formats.add_theme_constant_override("h_separation", 12)
	parent.add_child(formats)
	var group := ButtonGroup.new()
	for entry in [["2D", Stereo.Mode.MONO], ["Half-SBS", Stereo.Mode.HALF_SBS], ["Full-SBS", Stereo.Mode.FULL_SBS]]:
		_choice(entry[0], entry[1] == stereo_mode, group, formats, func(): stereo_mode = entry[1]; stereo_selected.emit(entry[1]))
	var swap := CheckBox.new()
	swap.text = "Swap left and right eyes"
	swap.custom_minimum_size.y = 56
	swap.button_pressed = swap_eyes
	swap.toggled.connect(func(enabled: bool): swap_eyes = enabled; eyes_swapped.emit())
	parent.add_child(swap)
	Widgets.label("Environment", parent, 26)
	var environments := HBoxContainer.new()
	parent.add_child(environments)
	var environment_group := ButtonGroup.new()
	for value in ["Void", "Theatre"]:
		_choice(value, value == settings.environment, environment_group, environments,
			func(): settings.environment = value; screen_changed.emit(); _save())

func _reset_screen() -> void:
	settings.reset_screen()
	dragging_slider = false
	var section := sections[1]
	for child in section.get_children():
		section.remove_child(child)
		child.queue_free()
	_build_screen(section)
	_adapt_columns()
	var reset: Button = section.get_child(0).get_child(1)
	reset.grab_focus.call_deferred()
	screen_changed.emit()
	_save()

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
	var slider := HSlider.new()
	slider.accessibility_name = entry[0]
	slider.custom_minimum_size.y = 48
	slider.min_value = entry[2]
	slider.max_value = entry[3]
	slider.step = 0.05
	slider.value = settings.get(entry[1])
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
	if sort_choices != null:
		sort_choices.columns = 3 if size.x >= 980 else (2 if size.x >= 650 else 1)
	if screen_dimensions != null:
		screen_dimensions.columns = 2 if size.x >= 650 else 1
