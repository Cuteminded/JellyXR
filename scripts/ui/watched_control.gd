extends VBoxContainer

signal changed

var api: JellyfinClient
var item: Dictionary
var button: Button
var status: Label
var busy := false

func _ready() -> void:
	button = Widgets.button("", _toggle, self)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	status = Widgets.label("", self, 18)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.x = 200
	status.hide()
	_refresh()

func _refresh() -> void:
	var user: Dictionary = item.get("UserData", {}) if item.get("UserData") else {}
	button.text = "Mark as unwatched" if user.get("Played", false) else "Mark as watched"
	button.accessibility_name = button.text + " " + DetailsMetadata.title(item)

func _toggle() -> void:
	if busy: return
	busy = true
	button.disabled = true
	status.text = "Saving..."
	status.show()
	var user: Dictionary = item.get("UserData", {}) if item.get("UserData") else {}
	var result := await api.set_watched(str(item.Id), not user.get("Played", false))
	if not is_inside_tree(): return
	busy = false
	button.disabled = false
	if not result.ok:
		status.text = result.error
		return
	if not result.data is Dictionary or not result.data.get("Played") is bool:
		status.text = "Could not confirm watched status. Reopen the item to refresh it."
		return
	var updated := user.duplicate(true)
	updated.merge(result.data, true)
	item["UserData"] = updated
	status.hide()
	_refresh()
	changed.emit()
