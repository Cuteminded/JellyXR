class_name VRKeyboard
extends PanelContainer

var target: LineEdit
var uppercase := false
var editor: LineEdit
var heading: Label

func _ready() -> void:
	theme = Widgets.theme()
	position = (get_viewport_rect().size - Vector2(830, 680)) / 2.0
	custom_minimum_size = Vector2(830, 680)
	var background := StyleBoxFlat.new()
	background.bg_color = Color("142632")
	background.set_border_width_all(3)
	background.border_color = Color("6de3cf")
	background.set_content_margin_all(22)
	add_theme_stylebox_override("panel", background)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	add_child(body)
	heading = Widgets.label("Type", body)
	editor = Widgets.input("", body)
	editor.virtual_keyboard_enabled = false
	editor.text_changed.connect(func(value: String):
		if is_instance_valid(target): target.text = value)
	var shortcuts := HBoxContainer.new()
	body.add_child(shortcuts)
	for prefix in ["http://", "https://"]:
		var key := Widgets.button(prefix, _insert.bind(prefix), shortcuts)
		key.focus_mode = Control.FOCUS_NONE
	for letters in ["1234567890", "qwertyuiop", "asdfghjkl", "zxcvbnm", ":/.-_@!?#", "$%&*+=()"]:
		var row := HBoxContainer.new()
		body.add_child(row)
		for letter in letters:
			var key := Widgets.button(letter, _type.bind(letter), row)
			key.custom_minimum_size = Vector2(64, 52)
			key.focus_mode = Control.FOCUS_NONE
	var actions := HBoxContainer.new()
	body.add_child(actions)
	Widgets.button("Shift", func(): uppercase = not uppercase, actions)
	Widgets.button("Space", _type.bind(" "), actions)
	Widgets.button("Backspace", _backspace, actions)
	Widgets.button("Done", hide, actions)

func edit(field: LineEdit) -> void:
	if not is_instance_valid(field): return
	target = field
	heading.text = field.placeholder_text
	editor.secret = field.secret
	editor.text = field.text
	editor.caret_column = editor.text.length()
	show()
	editor.grab_focus.call_deferred()

func _type(value: String) -> void:
	_insert(value.to_upper() if uppercase else value)

func _insert(value: String) -> void:
	if is_instance_valid(target):
		editor.insert_text_at_caret(value)
		target.text = editor.text

func _backspace() -> void:
	if not is_instance_valid(target): return
	if editor.has_selection():
		editor.delete_text(editor.get_selection_from_column(), editor.get_selection_to_column())
	elif editor.caret_column > 0:
		editor.delete_char_at_caret()
	target.text = editor.text

