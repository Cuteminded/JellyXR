class_name ControllerMappingHand
extends Control

signal button_selected(key: String)

var model: ControllerDiagramModel
var hand := "left_hand"
var bindings: ControllerBindings
var selected_key := ""
var binding_buttons: Dictionary = {}
var hotspots: Dictionary = {}
var action_labels: Dictionary = {}
var diagram_rect: Rect2

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	custom_minimum_size = Vector2(350, 360)
	for action in model.button_positions:
		var key: String = hand + "/" + action
		if not bindings.buttons().has(key): continue
		_build_button(key, model.button_labels.get(action, action))
	custom_minimum_size.y = maxf(custom_minimum_size.y, binding_buttons.size() * 70.0)
	resized.connect(_layout)
	_layout()
	refresh()

func _build_button(key: String, title: String) -> void:
	var button := Widgets.button("", func(): button_selected.emit(key), self)
	button.toggle_mode = true
	button.custom_minimum_size = Vector2.ZERO
	binding_buttons[key] = button
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right"]: margin.add_theme_constant_override("margin_" + edge, 12)
	for edge in ["top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 6)
	button.add_child(margin)
	var labels := VBoxContainer.new()
	labels.add_theme_constant_override("separation", 3)
	margin.add_child(labels)
	var label := Widgets.label(title, labels, 15)
	label.add_theme_color_override("font_color", Color("a4b2c6"))
	var value := Widgets.label("", labels, 18)
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	action_labels[key] = value
	for node in [margin, labels, label, value]: node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hotspot := Widgets.button("", func(): button_selected.emit(key), self)
	hotspot.custom_minimum_size = Vector2.ZERO
	for state in ["normal", "pressed", "disabled"]:
		hotspot.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for state in ["hover", "focus"]:
		var style := Widgets.surface(Color(0.43, 0.89, 0.81, 0.12), 22)
		style.set_border_width_all(2)
		style.border_color = Color("6de3cf")
		hotspot.add_theme_stylebox_override(state, style)
	hotspots[key] = hotspot

func _layout() -> void:
	var diagram_width := clampf(size.x * 0.38, 150.0, 200.0)
	var right_hand := hand == "right_hand"
	var diagram_x := 0.0 if right_hand else size.x - diagram_width
	diagram_rect = Rect2(diagram_x, 20, diagram_width, diagram_width * model.canvas_size.y / model.canvas_size.x)
	var label_width := size.x - diagram_width - 24
	var label_x := diagram_width + 24 if right_hand else 0.0
	var index := 0
	for key in binding_buttons:
		var button: Button = binding_buttons[key]
		button.position = Vector2(label_x, index * 70)
		button.size = Vector2(label_width, 64)
		var hotspot: Button = hotspots[key]
		hotspot.size = Vector2.ONE * model.hotspot_diameter
		hotspot.position = _point(key) - hotspot.size / 2
		index += 1
	queue_redraw()

func _point(key: String) -> Vector2:
	var position_in_model := model.button_position(key.get_slice("/", 1), hand == "right_hand")
	return diagram_rect.position + position_in_model * diagram_rect.size / model.canvas_size

func _draw() -> void:
	if model == null: return
	if hand == "right_hand" and model.mirror_right:
		draw_set_transform(diagram_rect.position + Vector2(diagram_rect.size.x, 0), 0, Vector2(-1, 1))
		draw_texture_rect(model.texture, Rect2(Vector2.ZERO, diagram_rect.size), false)
		draw_set_transform(Vector2.ZERO)
	else:
		draw_texture_rect(model.texture, diagram_rect, false)
	for key in binding_buttons:
		var button: Button = binding_buttons[key]
		var start := button.position + Vector2(0 if hand == "right_hand" else button.size.x, button.size.y / 2)
		var elbow := start + Vector2(-12 if hand == "right_hand" else 12, 0)
		var color := Color("6de3cf") if key == selected_key else Color("4c617a")
		draw_polyline(PackedVector2Array([start, elbow, _point(key)]), color, 2.0 if key == selected_key else 1.0, true)
	if hotspots.has(selected_key):
		draw_arc(_point(selected_key), model.hotspot_diameter / 2 + 3, 0, TAU, 48, Color("6de3cf"), 2.5, true)

func refresh() -> void:
	for key in binding_buttons:
		var action := bindings.action_for(key)
		action_labels[key].text = ControllerBindings.ACTIONS[action]
		var title: String = model.button_labels.get(key.get_slice("/", 1), key)
		var accessible := "%s controller, %s, %s" % ["Right" if hand == "right_hand" else "Left", title, ControllerBindings.ACTIONS[action]]
		binding_buttons[key].accessibility_name = accessible
		hotspots[key].accessibility_name = accessible
		binding_buttons[key].button_pressed = key == selected_key
	queue_redraw()
