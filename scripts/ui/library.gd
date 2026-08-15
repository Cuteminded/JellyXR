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

func _ready() -> void:
	add_theme_constant_override("separation", 18)
	artwork = ArtworkLoader.new()
	artwork.api = api
	add_child(artwork)
	var tools := HBoxContainer.new()
	add_child(tools)
	field = Widgets.input("Search " + ("movies and shows" if library_id.is_empty() else library_name), tools)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.text_submitted.connect(refresh)
	Widgets.button("Search", func(): refresh(field.text), tools)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 24)
	scroll.add_child(content)
	refresh()

func refresh(term: String = "") -> void:
	generation += 1
	var current := generation
	busy = true
	search = term
	offset = 0
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
	if busy: return
	busy = true
	var result := await api.library(search, offset, library_id)
	if current != generation: return
	busy = false
	if not result.ok:
		status.emit(result.error)
		var retry := Widgets.button("Retry", func(): pass, content)
		retry.pressed.connect(func(): retry.queue_free(); _more(current))
		return
	var items: Array = result.data.get("Items", [])
	if offset == 0:
		if search.is_empty() and not items.is_empty():
			var hero := LibraryHero.new()
			hero.item = items[0]
			hero.artwork = artwork
			hero.chosen.connect(func(item: Dictionary): selected.emit(item))
			content.add_child(hero)
			content.move_child(hero, 0)
		Widgets.label(("Your library" if library_id.is_empty() else library_name) if search.is_empty() else "Search results", content, 28)
	_cards(items)
	offset += items.size()
	status.emit("%d titles loaded" % offset if offset > 0 else "No matching titles.")
	if offset < int(result.data.get("TotalRecordCount", offset)):
		var next := Widgets.button("Load more", func(): pass, content)
		next.pressed.connect(func(): next.queue_free(); _more(current))

func _cards(items: Array, horizontal: bool = false) -> void:
	var holder: Container
	if horizontal:
		var scroll := ScrollContainer.new()
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.custom_minimum_size.y = 352
		content.add_child(scroll)
		holder = HBoxContainer.new()
		holder.add_theme_constant_override("separation", 18)
		scroll.add_child(holder)
	else:
		var grid := HFlowContainer.new()
		grid.add_theme_constant_override("h_separation", 18)
		grid.add_theme_constant_override("v_separation", 18)
		holder = grid
		content.add_child(holder)
	for item in items:
		var card := MediaCard.new()
		card.item = item
		card.artwork = artwork
		card.chosen.connect(func(chosen: Dictionary): selected.emit(chosen))
		holder.add_child(card)
