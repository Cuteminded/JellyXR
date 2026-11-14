extends VBoxContainer

var api: JellyfinClient
var item: Dictionary
var button: Button
var status: Label

func _ready() -> void:
	button = Widgets.button("", _toggle, self)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	status = Widgets.label("", self, 18)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.hide()
	_refresh()

func _user_data() -> Dictionary:
	var data: Variant = item.get("UserData")
	return data if data is Dictionary else {}

func _refresh() -> void:
	button.text = "Remove from favourites" if _user_data().get("IsFavorite", false) else "Add to favourites"
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
