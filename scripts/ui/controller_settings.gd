class_name ControllerSettings
extends VBoxContainer

signal changed

var bindings: ControllerBindings
var left_model: ControllerDiagramModel = preload("res://assets/controllers/generic.tres")
var right_model: ControllerDiagramModel = preload("res://assets/controllers/generic.tres")
var draft := ControllerBindings.new()
var binding_buttons: Dictionary = {}
var action_buttons: Dictionary = {}
var hand_views: Array[ControllerMappingHand] = []
var hands: BoxContainer
var editor: ControllerActionPopup
var reset_button: Button
var apply_button: Button
var selected_key := ""
var save_failed := false

func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	draft.overrides = bindings.overrides.duplicate()
	add_theme_constant_override("separation", 16)
	_hint("Choose a button or its action to change the mapping.")
	hands = BoxContainer.new()
	hands.add_theme_constant_override("separation", 28)
	add_child(hands)
	_build_hand("left_hand", left_model)
	_build_hand("right_hand", right_model)
	_build_editor()
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(spacer)
	_build_footer()
	resized.connect(_adapt_layout)
	visibility_changed.connect(_close_if_hidden)
	_adapt_layout()
	refresh()

func _hint(message: String) -> void:
	var label := Widgets.label(message, self, 18)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color("a4aec0"))

func _build_hand(hand: String, model: ControllerDiagramModel) -> void:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hands.add_child(column)
	var label := Widgets.label("Left controller" if hand == "left_hand" else "Right controller", column, 22)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if hand == "right_hand" else HORIZONTAL_ALIGNMENT_LEFT
	var view := ControllerMappingHand.new()
	view.hand = hand
	view.model = model
	view.bindings = draft
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.button_selected.connect(_select_button)
	column.add_child(view)
	hand_views.append(view)
	binding_buttons.merge(view.binding_buttons)

func _build_editor() -> void:
	editor = ControllerActionPopup.new()
	editor.action_selected.connect(_assign)
	editor.closed.connect(_close_editor)
	add_child(editor)
	action_buttons = editor.action_buttons

func _build_footer() -> void:
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", 16)
	add_child(footer)
	reset_button = Widgets.button("Reset to defaults", _reset, footer)
	apply_button = Widgets.button("Apply changes", _apply, footer)
	Widgets.accent(apply_button)

func _adapt_layout() -> void:
	hands.vertical = size.x < 780

func _select_button(key: String) -> void:
	selected_key = key
	var model := right_model if key.begins_with("right_hand/") else left_model
	var title := "%s controller\n%s" % ["Right" if key.begins_with("right_hand/") else "Left", model.button_labels.get(key.get_slice("/", 1), key)]
	editor.show_choices(title, draft.action_for(key))
	refresh()

func _close_editor() -> void:
	var previous_key := selected_key
	selected_key = ""
	editor.hide()
	refresh()
	if is_visible_in_tree() and binding_buttons.has(previous_key):
		binding_buttons[previous_key].grab_focus()

func _close_if_hidden() -> void:
	if editor != null and not is_visible_in_tree(): _close_editor()

func _assign(action: String) -> void:
	if selected_key.is_empty(): return
	draft.assign(selected_key, action)
	_close_editor()

func _reset() -> void:
	draft.overrides.clear()
	_close_editor()

func _apply() -> void:
	bindings.overrides = draft.overrides.duplicate()
	_close_editor()
	changed.emit()

func show_save_result(result: Error) -> void:
	save_failed = result != OK
	refresh()

func refresh() -> void:
	for view in hand_views:
		view.selected_key = selected_key
		view.refresh()
	var dirty := draft.overrides != bindings.overrides
	apply_button.disabled = not dirty and not save_failed
