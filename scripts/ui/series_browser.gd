class_name SeriesBrowser
extends VBoxContainer

signal play_requested(item: Dictionary)
signal section_changed

var api: JellyfinClient
var artwork: ArtworkLoader
var series_id := ""
var season_grid: HFlowContainer
var season_section: VBoxContainer
var episode_section: VBoxContainer
var episode_list: VBoxContainer
var episode_heading: Label
var season_description: Label
var all_seasons_button: Button
var generation := 0

func _ready() -> void:
	add_theme_constant_override("separation", 20)
	season_section = VBoxContainer.new()
	season_section.add_theme_constant_override("separation", 18)
	add_child(season_section)
	Widgets.label("Seasons", season_section, 28)
	season_grid = HFlowContainer.new()
	season_grid.add_theme_constant_override("h_separation", 18)
	season_grid.add_theme_constant_override("v_separation", 18)
	season_section.add_child(season_grid)
	episode_section = VBoxContainer.new()
	episode_section.add_theme_constant_override("separation", 18)
	add_child(episode_section)
	var navigation := HBoxContainer.new()
	episode_section.add_child(navigation)
	all_seasons_button = Widgets.button("All seasons", _show_seasons, navigation)
	episode_heading = _label("", episode_section, 28)
	season_description = _label("", episode_section, 22)
	episode_list = VBoxContainer.new()
	episode_list.add_theme_constant_override("separation", 16)
	episode_section.add_child(episode_list)
	episode_section.hide()
	load_seasons()

func load_seasons() -> void:
	generation += 1
	var current := generation
	_clear(season_grid)
	_label("Loading seasons...", season_grid, 22)
	var result := await api.seasons(series_id)
	if not _current(current): return
	_clear(season_grid)
	if not result.ok:
		_label("Could not load seasons.", season_grid, 22)
		Widgets.button("Retry seasons", load_seasons, season_grid)
		return
	var seasons: Array = result.data.get("Items", [])
	if seasons.is_empty():
		_label("No seasons available.", season_grid, 22)
	for season in seasons:
		var card := MediaCard.new()
		card.item = season
		card.artwork = artwork
		card.chosen.connect(open_season)
		season_grid.add_child(card)

func open_season(season: Dictionary) -> void:
	generation += 1
	var current := generation
	season_section.hide()
	episode_section.show()
	all_seasons_button.grab_focus()
	episode_heading.text = str(season.get("Name", "Season")) + " episodes"
	season_description.text = str(season.get("Overview") if season.get("Overview") else "")
	season_description.visible = not season_description.text.is_empty()
	_clear(episode_list)
	_label("Loading episodes...", episode_list, 22)
	section_changed.emit()
	var items: Array = []
	while true:
		var result := await api.episodes(series_id, str(season.Id), items.size())
		if not _current(current): return
		if not result.ok:
			_clear(episode_list)
			_label("Could not load episodes.", episode_list, 22)
			Widgets.button("Retry episodes", open_season.bind(season), episode_list)
			section_changed.emit()
			return
		var batch: Array = result.data.get("Items", [])
		items.append_array(batch)
		if batch.is_empty() or items.size() >= int(result.data.get("TotalRecordCount", items.size())): break
	_clear(episode_list)
	if items.is_empty(): _label("No episodes available in this season.", episode_list, 22)
	for episode in items:
		var card := EpisodeCard.new()
		card.item = episode
		card.artwork = artwork
		card.chosen.connect(func(chosen: Dictionary): play_requested.emit(chosen))
		episode_list.add_child(card)
	section_changed.emit()

func _show_seasons() -> void:
	generation += 1
	episode_section.hide()
	season_section.show()
	section_changed.emit()
	if season_grid.get_child_count() > 0:
		var first := season_grid.get_child(0) as Control
		if first and first.focus_mode != Control.FOCUS_NONE: first.grab_focus()

func _current(current: int) -> bool:
	return current == generation and is_inside_tree()

func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _label(value: String, parent: Node, font_size: int) -> Label:
	var label := Widgets.label(value, parent, font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label
