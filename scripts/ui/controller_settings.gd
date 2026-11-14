class_name ControllerSettings
extends VBoxContainer

signal changed

var bindings: ControllerBindings
var controller_profiles: Dictionary[String, ControllerBindings] = {}
var left_model: ControllerDiagramModel = preload("res://assets/controllers/generic.tres")
var right_model: ControllerDiagramModel = preload("res://assets/controllers/generic.tres")
var draft := ControllerBindings.new()
var profile_drafts: Dictionary[String, ControllerBindings] = {}
var left_profile := ""
var right_profile := ""
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
	for profile in controller_profiles:
		var profile_draft := ControllerBindings.new(profile)
		profile_draft.overrides = controller_profiles[profile].overrides.duplicate()
		profile_drafts[profile] = profile_draft
	add_theme_constant_override("separation", 16)
	_hint("Choose a button or its action to change the mapping.")
	hands = BoxContainer.new()
	hands.add_theme_constant_override("separation", 28)
	add_child(hands)
	_update_hands()
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

func _process(_delta: float) -> void:
	if is_visible_in_tree() and _update_hands():
		_close_editor()

func _update_hands() -> bool:
	var left := _editable_profile(&"left_hand")
	var right := _editable_profile(&"right_hand")
	if not hand_views.is_empty() and left == left_profile and right == right_profile:
		return false
	left_profile = left
	right_profile = right
	for column in hands.get_children():
		hands.remove_child(column)
		column.queue_free()
	hand_views.clear()
	binding_buttons.clear()
	_build_hand("left_hand", ControllerBindings.PROFILES.get(left, {}).get("left_model", left_model), profile_drafts.get(left, draft))
	_build_hand("right_hand", ControllerBindings.PROFILES.get(right, {}).get("right_model", right_model), profile_drafts.get(right, draft))
	return true

func _editable_profile(hand: StringName) -> String:
	var profile := ControllerBindings.active_profile(hand)
	return profile if profile_drafts.has(profile) else ""

func _hint(message: String) -> void:
	var label := Widgets.label(message, self, 18)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color("a4aec0"))

func _build_hand(hand: String, model: ControllerDiagramModel, hand_bindings: ControllerBindings) -> void:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hands.add_child(column)
	var label := Widgets.label("Left controller" if hand == "left_hand" else "Right controller", column, 22)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if hand == "right_hand" else HORIZONTAL_ALIGNMENT_LEFT
	var view := ControllerMappingHand.new()
	view.hand = hand
	view.model = model
	view.bindings = hand_bindings
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
	var right := key.begins_with("right_hand/")
	var view := hand_views[1 if right else 0]
	var title := "%s controller\n%s" % ["Right" if right else "Left", view.model.button_labels.get(key.get_slice("/", 1), key)]
	editor.show_choices(title, view.bindings.action_for(key))
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
	var view := hand_views[1 if selected_key.begins_with("right_hand/") else 0]
	view.bindings.assign(selected_key, action)
	_close_editor()

func _reset() -> void:
	for view in hand_views:
		for key in view.bindings.buttons():
			if key.begins_with(view.hand + "/"):
				view.bindings.overrides.erase(key)
	_close_editor()

func _apply() -> void:
	bindings.overrides = draft.overrides.duplicate()
	for profile in profile_drafts:
		controller_profiles[profile].overrides = profile_drafts[profile].overrides.duplicate()
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
	for profile in profile_drafts:
		dirty = dirty or profile_drafts[profile].overrides != controller_profiles[profile].overrides
	apply_button.disabled = not dirty and not save_failed
