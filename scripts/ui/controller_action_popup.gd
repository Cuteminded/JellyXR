class_name ControllerActionPopup
extends CanvasLayer

signal action_selected(action: String)
signal closed

var panel: PanelContainer
var heading: Label
var action_buttons: Dictionary = {}
var backdrop: Button

func _ready() -> void:
	layer = 20
	var overlay := Control.new()
	overlay.theme = Widgets.theme()
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop = Button.new()
	backdrop.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "focus"]:
		backdrop.add_theme_stylebox_override(state, Widgets.surface(Color(0.02, 0.04, 0.08, 0.72), 0))
	backdrop.pressed.connect(func(): closed.emit())
	overlay.add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var surface := Widgets.surface(Color("162133"), 20, 24)
	surface.set_border_width_all(1)
	surface.border_color = Color("3d4c63")
	panel.add_theme_stylebox_override("panel", surface)
	overlay.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	panel.add_child(body)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	body.add_child(header)
	heading = Widgets.label("", header, 22)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var close := Widgets.button("Close", func(): closed.emit(), header)
	close.custom_minimum_size.x = 96
	var options := VBoxContainer.new()
	options.add_theme_constant_override("separation", 8)
	body.add_child(options)
	var focus_buttons: Array[Button] = [close]
	for action in ControllerBindings.ACTIONS:
		var button := Widgets.button(ControllerBindings.ACTIONS[action], func(): action_selected.emit(action), options)
		button.toggle_mode = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		PlayerQuickAccess.style_button(button)
		action_buttons[action] = button
		focus_buttons.append(button)
	for index in range(focus_buttons.size()):
		var button := focus_buttons[index]
		button.focus_previous = button.get_path_to(focus_buttons[(index - 1 + focus_buttons.size()) % focus_buttons.size()])
		button.focus_next = button.get_path_to(focus_buttons[(index + 1) % focus_buttons.size()])
		button.focus_neighbor_top = button.focus_previous
		button.focus_neighbor_bottom = button.focus_next
		button.focus_neighbor_left = button.get_path_to(button)
		button.focus_neighbor_right = button.get_path_to(button)
	get_viewport().size_changed.connect(_fit)
	panel.minimum_size_changed.connect(_fit)
	hide()

func show_choices(title: String, selected_action: String) -> void:
	heading.text = title
	for action in action_buttons:
		action_buttons[action].button_pressed = action == selected_action
	show()
	_fit()
	_fit.call_deferred()
	action_buttons[selected_action].grab_focus()

func _fit() -> void:
	if not visible: return
	var viewport_size := get_viewport().get_visible_rect().size
	panel.size.x = minf(520, viewport_size.x - 48)
	panel.size.y = panel.get_combined_minimum_size().y
	panel.position = (viewport_size - panel.size) / 2

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		closed.emit()
		get_viewport().set_input_as_handled()
