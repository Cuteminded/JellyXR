class_name LibraryView
extends VBoxContainer

signal selected(item: Dictionary)
signal status(message: String)
var api: JellyfinClient
var library_id := ""
var library_name := "Home"
var field: LineEdit
var content: VBoxContainer
var artwork: ArtworkLoader
var offset := 0
var search := ""
var generation := 0
var busy := false
var has_more := false
var scroll: ScrollContainer
var grid: HFlowContainer
static var previous_hero_ids: Dictionary = {}

const LOAD_AHEAD_PIXELS := 400.0

func _ready() -> void:
	add_theme_constant_override("separation", 18)
	artwork = ArtworkLoader.new()
	artwork.api = api
	add_child(artwork)
	var tools := HBoxContainer.new()
	add_child(tools)
	field = Widgets.input("Search " + library_name, tools)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.text_submitted.connect(refresh)
	Widgets.button("Search", func(): refresh(field.text), tools)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 24)
	scroll.add_child(content)
	var scrollbar := scroll.get_v_scroll_bar()
	scrollbar.value_changed.connect(func(_value: float): _check_more.call_deferred())
	scrollbar.changed.connect(func(): _check_more.call_deferred())
	refresh()

func refresh(term: String = "") -> void:
	generation += 1
	var current := generation
	busy = true
	has_more = false
	scroll.scroll_vertical = 0
	search = term
	offset = 0
	grid = null
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	status.emit("Loading " + library_name.to_lower() + "...")
	if term.is_empty() and library_id.is_empty():
		var resume := await api.resume_items()
		if current != generation: return
		if resume.ok and not resume.data.get("Items", []).is_empty():
			Widgets.label("Continue watching", content, 28)
			_cards(resume.data.Items, true)
	busy = false
	await _more(current)

func _more(current: int) -> void:
	if busy or current != generation: return
	busy = true
	has_more = false
	var result := await api.library(search, offset, library_id)
	if current != generation: return
	if not result.ok:
		busy = false
		status.emit(result.error)
		var retry := Widgets.button("Retry", func(): pass, content)
		retry.pressed.connect(func(): retry.queue_free(); _more(current))
		return
	var items: Array = result.data.get("Items", [])
	if offset == 0:
		if search.is_empty() and items.any(func(item: Dictionary): return item.get("Type", "") != "Photo"):
			var hero := LibraryHero.new()
			hero.item = _choose_hero(items.filter(func(item: Dictionary): return item.get("Type", "") != "Photo"))
			hero.artwork = artwork
			hero.chosen.connect(func(item: Dictionary): selected.emit(item))
			content.add_child(hero)
			content.move_child(hero, 0)
		Widgets.label(("Recently Added" if library_id.is_empty() else library_name) if search.is_empty() else "Search results", content, 28)
	_cards(items)
	offset += items.size()
	status.emit("%d titles loaded" % offset if offset > 0 else "No matching titles.")
	has_more = not items.is_empty() and offset < int(result.data.get("TotalRecordCount", offset))
	await get_tree().process_frame
	await get_tree().process_frame
	if current != generation: return
	busy = false
	_check_more.call_deferred()

func _choose_hero(items: Array) -> Dictionary:
	var previous_id := str(previous_hero_ids.get(library_id, ""))
	var candidates := items.filter(func(item: Dictionary): return str(item.get("Id", "")) != previous_id)
	var chosen: Dictionary = (items if candidates.is_empty() else candidates).pick_random()
	previous_hero_ids[library_id] = str(chosen.get("Id", ""))
	return chosen

func _check_more() -> void:
	if busy or not has_more or not is_inside_tree(): return
	var scrollbar := scroll.get_v_scroll_bar()
	var remaining := scrollbar.max_value - scrollbar.page - scrollbar.value
	if remaining <= LOAD_AHEAD_PIXELS:
		_more(generation)

func _cards(items: Array, horizontal: bool = false) -> void:
	var holder: Container
	if horizontal:
		var row_scroll := ScrollContainer.new()
		row_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		row_scroll.custom_minimum_size.y = 352
		content.add_child(row_scroll)
		holder = HBoxContainer.new()
		holder.add_theme_constant_override("separation", 18)
		row_scroll.add_child(holder)
	else:
		if grid == null:
			grid = HFlowContainer.new()
			grid.add_theme_constant_override("h_separation", 18)
			grid.add_theme_constant_override("v_separation", 18)
			content.add_child(grid)
		holder = grid
	for item in items:
		var card := MediaCard.new()
		card.item = item
		card.artwork = artwork
		card.chosen.connect(func(chosen: Dictionary): selected.emit(chosen))
		holder.add_child(card)
