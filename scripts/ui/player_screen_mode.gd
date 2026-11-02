class_name PlayerScreenMode
extends VBoxContainer

signal stereo_selected(value: int)
signal projection_selected(value: int)
signal eyes_swapped(enabled: bool)

var state_provider: Callable
var stereo_buttons: Dictionary = {}
var projection_buttons: Dictionary = {}
var swap_button: CheckButton

func _ready() -> void:
	add_theme_constant_override("separation", 10)
	Widgets.label("Projection", self, 20)
	var projections := _grid(3)
	var projection_group := ButtonGroup.new()
	for entry in [["Screen", VideoProjection.Mode.SCREEN], ["180°", VideoProjection.Mode.EQUIRECTANGULAR_180], ["360°", VideoProjection.Mode.EQUIRECTANGULAR]]:
		projection_buttons[entry[1]] = _choice(entry[0], projection_group, projections, func(): projection_selected.emit(entry[1]))
	add_child(HSeparator.new())
	Widgets.label("Picture format", self, 20)
	var stereo_group := ButtonGroup.new()
	stereo_buttons[Stereo.Mode.MONO] = _choice("2D", stereo_group, self, func(): stereo_selected.emit(Stereo.Mode.MONO))
	var formats := _grid(2)
	for entry in [["Half-SBS", Stereo.Mode.HALF_SBS], ["Full-SBS", Stereo.Mode.FULL_SBS], ["Half top-bottom", Stereo.Mode.HALF_TOP_BOTTOM], ["Top-bottom", Stereo.Mode.TOP_BOTTOM]]:
		stereo_buttons[entry[1]] = _choice(entry[0], stereo_group, formats, func(): stereo_selected.emit(entry[1]))
	add_child(HSeparator.new())
	swap_button = CheckButton.new()
	swap_button.text = "Swap left and right eyes"
	swap_button.accessibility_name = swap_button.text
	swap_button.custom_minimum_size.y = 48
	swap_button.add_theme_font_size_override("font_size", 18)
	PlayerQuickAccess.style_button(swap_button)
	swap_button.toggled.connect(func(enabled: bool): eyes_swapped.emit(enabled))
	add_child(swap_button)

func _grid(columns: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	add_child(grid)
	return grid

func _choice(label: String, group: ButtonGroup, parent: Node, callback: Callable) -> Button:
	var button := Widgets.button(label, callback, parent)
	button.accessibility_name = label
	button.toggle_mode = true
	button.button_group = group
	button.custom_minimum_size = Vector2(0, 48)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 18)
	PlayerQuickAccess.style_button(button)
	return button

func refresh() -> void:
	if not state_provider.is_valid(): return
	var state: Dictionary = state_provider.call()
	for mode in stereo_buttons:
		stereo_buttons[mode].set_pressed_no_signal(mode == state.get("stereo", Stereo.Mode.MONO))
	for projection in projection_buttons:
		projection_buttons[projection].set_pressed_no_signal(projection == state.get("projection", VideoProjection.Mode.SCREEN))
	swap_button.set_pressed_no_signal(state.get("swap_eyes", false))
