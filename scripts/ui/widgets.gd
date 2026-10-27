class_name Widgets
extends RefCounted

static func button(text: String, action: Callable, parent: Node) -> Button:
	var result := Button.new()
	result.text = text
	result.custom_minimum_size = Vector2(140, 56)
	result.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	result.pressed.connect(action)
	parent.add_child(result)
	return result

static func label(text: String, parent: Node, size: int = 24) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", size)
	parent.add_child(result)
	return result

static func input(placeholder: String, parent: Node, secret: bool = false) -> LineEdit:
	var result := LineEdit.new()
	result.placeholder_text = placeholder
	result.secret = secret
	result.virtual_keyboard_enabled = false
	result.custom_minimum_size.y = 60
	parent.add_child(result)
	return result

static func watched_badge(image_frame: PanelContainer) -> Control:
	var overlay := Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image_frame.add_child(overlay)
	var badge := TextureRect.new()
	badge.texture = preload("res://assets/icons/watched.svg")
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(badge)
	badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	badge.offset_left = -36
	badge.offset_top = 8
	badge.offset_right = -8
	badge.offset_bottom = 36
	return overlay

static func theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 22
	result.set_color("font_color", "Label", Color("f3f5fa"))
	result.set_color("font_color", "Button", Color("f3f5fa"))
	result.set_color("font_disabled_color", "Button", Color("8793a8"))
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var box := surface(Color("202a3d") if state == "normal" else Color("34435b"), 12, 16)
		if state in ["hover", "focus"]:
			box.set_border_width_all(3)
			box.border_color = Color("6de3cf")
		result.set_stylebox(state, "Button", box)
	var input_normal := surface(Color("1a2435"), 12, 16)
	input_normal.set_border_width_all(1)
	input_normal.border_color = Color("3d4c63")
	result.set_stylebox("normal", "LineEdit", input_normal)
	var input_focus := surface(Color("162133"), 12, 16)
	input_focus.set_border_width_all(2)
	input_focus.border_color = Color("6de3cf")
	result.set_stylebox("focus", "LineEdit", input_focus)
	result.set_color("font_color", "LineEdit", Color("f3f5fa"))
	result.set_color("font_placeholder_color", "LineEdit", Color("a4aec0"))
	return result

static func surface(color: Color, radius: int = 16, padding: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(padding)
	return style

static func accent(button_node: Button) -> void:
	button_node.add_theme_stylebox_override("normal", surface(Color("6de3cf"), 12, 16))
	button_node.add_theme_stylebox_override("hover", surface(Color("a5f2e5"), 12, 16))
	button_node.add_theme_stylebox_override("pressed", surface(Color("47bda9"), 12, 16))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button_node.add_theme_color_override(state, Color("071c20"))
