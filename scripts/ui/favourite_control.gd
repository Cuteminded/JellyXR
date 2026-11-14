extends VBoxContainer

var api: JellyfinClient
var item: Dictionary
var button: Button
var status: Label

func _ready() -> void:
	button = Widgets.button("", _toggle, self)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.icon = preload("res://assets/icons/favourite.svg")
	button.add_theme_constant_override("icon_max_width", 21)
	button.add_theme_constant_override("h_separation", 9)
	status = Widgets.label("", self, 18)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.hide()
	_refresh()

func _user_data() -> Dictionary:
	var data: Variant = item.get("UserData")
	return data if data is Dictionary else {}

func _refresh() -> void:
	var saved: bool = _user_data().get("IsFavorite", false)
	button.text = "Remove from favourites" if saved else "Add to favourites"
	var icon_color := Color("6de3cf") if saved else Color("c2cbd9")
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		button.add_theme_color_override(state, icon_color)
	button.accessibility_name = button.text + " for " + DetailsMetadata.title(item)

func _toggle() -> void:
	if button.disabled: return
	button.disabled = true
	status.text = "Saving..."
	status.show()
	var result := await api.set_favourite(str(item.Id), not _user_data().get("IsFavorite", false))
	if not is_inside_tree(): return
	button.disabled = false
	if not result.ok:
		status.text = result.error
		return
	if not result.data is Dictionary or not result.data.get("IsFavorite") is bool:
		status.text = "Could not confirm favourite status. Reopen the title to refresh it."
		return
	var updated := _user_data()
	updated["IsFavorite"] = result.data.IsFavorite
	item["UserData"] = updated
	status.hide()
	_refresh()
