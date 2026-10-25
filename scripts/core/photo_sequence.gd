class_name PhotoSequence
extends RefCounted

var items: Array = []
var index := -1
var offset := 0
var has_more := false
var search := ""
var library_id := ""
var busy := false

func capture(library: LibraryView, selected: Dictionary) -> void:
	items.clear()
	if library.grid:
		for card in library.grid.get_children():
			if card.item.get("Type", "") == "Photo": items.append(card.item)
	index = items.find(selected)
	if index < 0:
		items = [selected]
		index = 0
	offset = library.offset
	has_more = library.has_more
	search = library.search
	library_id = library.library_id

func can_next() -> bool:
	return index + 1 < items.size() or has_more

func step(direction: int, api: JellyfinClient) -> Dictionary:
	if busy or index + direction < 0: return {}
	busy = true
	while direction > 0 and index + 1 >= items.size() and has_more:
		var result := await api.library(search, offset, library_id)
		if not result.ok:
			busy = false
			return {"error": result.error}
		var page: Array = result.data.get("Items", [])
		offset += page.size()
		has_more = not page.is_empty() and offset < int(result.data.get("TotalRecordCount", offset))
		for item in page:
			if item.get("Type", "") == "Photo": items.append(item)
	busy = false
	if index + direction >= items.size(): return {}
	index += direction
	return {"item": items[index]}
