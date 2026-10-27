class_name SeriesBrowser
extends VBoxContainer

signal play_requested(item: Dictionary)
signal version_requested(item: Dictionary)
signal section_changed

var api: JellyfinClient
var artwork: ArtworkLoader
var series_id := ""
var series_item: Dictionary = {}
var season_grid: HFlowContainer
var season_section: VBoxContainer
var episode_section: VBoxContainer
var episode_list: VBoxContainer
var episode_heading: Label
var season_description: Label
var all_seasons_button: Button
var generation := 0
var selected_season: Dictionary = {}
var navigation_host: HBoxContainer
var navigation: HBoxContainer
var watched_host: VBoxContainer
var watched_control: VBoxContainer
var next_up_section: VBoxContainer
var next_up_list: VBoxContainer

func _ready() -> void:
	add_theme_constant_override("separation", 20)
	next_up_section = VBoxContainer.new()
	next_up_section.add_theme_constant_override("separation", 18)
	add_child(next_up_section)
	Widgets.label("Next Up", next_up_section, 28)
	next_up_list = VBoxContainer.new()
	next_up_section.add_child(next_up_list)
	next_up_section.hide()
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
	navigation = HBoxContainer.new()
	navigation.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	navigation.add_theme_constant_override("separation", 12)
	(navigation_host if navigation_host != null else self).add_child(navigation)
	all_seasons_button = Widgets.button("All seasons", _show_seasons, navigation)
	all_seasons_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	navigation.add_child(spacer)
	watched_host = VBoxContainer.new()
	navigation.add_child(watched_host)
	navigation.hide()
	episode_heading = _label("", episode_section, 28)
	season_description = _label("", episode_section, 22)
	episode_list = VBoxContainer.new()
	episode_list.add_theme_constant_override("separation", 16)
	episode_section.add_child(episode_list)
	episode_section.hide()
	if selected_season.is_empty(): load_seasons()
	else: open_season(selected_season)

func load_seasons() -> void:
	generation += 1
	var current := generation
	_load_next_up(current)
	if series_item.is_empty(): series_item = {"Id": series_id, "Type": "Series"}
	all_seasons_button.hide()
	_set_watched_control(series_item, _series_watched_changed.bind(current), "Applies to every episode in every season of this series.")
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
	var all_watched := not seasons.is_empty()
	for season in seasons:
		var user: Dictionary = season.get("UserData", {}) if season.get("UserData") else {}
		all_watched = all_watched and bool(user.get("Played", false))
	var series_user: Dictionary = series_item.get("UserData", {}) if series_item.get("UserData") else {}
	series_user["Played"] = all_watched
	series_item["UserData"] = series_user
	watched_control._refresh()
	watched_control.button.disabled = seasons.is_empty()
	if seasons.is_empty():
		_label("No seasons available.", season_grid, 22)
	for season in seasons:
		var card := MediaCard.new()
		card.item = season
		card.artwork = artwork
		card.chosen.connect(open_season)
		season_grid.add_child(card)

func _load_next_up(current: int) -> void:
	next_up_section.hide()
	_clear(next_up_list)
	var result := await api.next_up(series_id)
	if not _current(current): return
	if not result.ok:
		next_up_section.show()
		_label("Could not load the next episode.", next_up_list, 22)
		Widgets.button("Retry Next Up", _load_next_up.bind(current), next_up_list)
		return
	var items: Array = result.data.get("Items", [])
	if items.is_empty(): return
	var card := EpisodeCard.new()
	card.item = items[0].duplicate(true)
	card.item["Type"] = "Episode"
	card.item["SeriesId"] = series_id
	card.artwork = artwork
	card.api = api
	card.chosen.connect(func(chosen: Dictionary): play_requested.emit(chosen))
	card.version_requested.connect(func(chosen: Dictionary): version_requested.emit(chosen))
	next_up_list.add_child(card)
	card.watched_control.changed.connect(load_seasons)
	next_up_section.show()

func open_season(season: Dictionary) -> void:
	selected_season = season.duplicate(true)
	generation += 1
	var current := generation
	next_up_section.hide()
	season_section.hide()
	episode_section.show()
	all_seasons_button.show()
	_set_watched_control(selected_season, _season_watched_changed.bind(current), "Applies to every episode in this season.")
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
		card.item = episode.duplicate(true)
		card.item["Type"] = "Episode"
		card.item["SeriesId"] = series_id
		card.item["SeasonId"] = str(season.Id)
		if card.item.get("ParentIndexNumber") == null:
			card.item["ParentIndexNumber"] = season.get("IndexNumber")
		card.artwork = artwork
		card.api = api
		card.chosen.connect(func(chosen: Dictionary): play_requested.emit(chosen))
		card.version_requested.connect(func(chosen: Dictionary): version_requested.emit(chosen))
		episode_list.add_child(card)
		card.watched_control.changed.connect(_refresh_season_watched)
	_refresh_season_watched()
	section_changed.emit()

func _refresh_season_watched() -> void:
	if watched_control.busy: return
	var all_watched := true
	var count := 0
	for card in episode_list.get_children():
		if not card is EpisodeCard: continue
		count += 1
		var user: Dictionary = card.item.get("UserData", {}) if card.item.get("UserData") else {}
		all_watched = all_watched and bool(user.get("Played", false))
	selected_season["UserData"] = {"Played": all_watched and count > 0}
	watched_control._refresh()
	watched_control.button.disabled = count == 0

func _set_watched_control(item: Dictionary, action: Callable, tooltip: String) -> void:
	navigation.show()
	_clear(watched_host)
	watched_control = preload("res://scripts/ui/watched_control.gd").new()
	watched_control.api = api
	watched_control.item = item
	watched_control.changed.connect(action)
	watched_host.add_child(watched_control)
	watched_control.button.disabled = true
	watched_control.button.tooltip_text = tooltip

func _series_watched_changed(current: int) -> void:
	if not _current(current): return
	await load_seasons()
	if _current(current + 1): watched_control.button.grab_focus()

func _season_watched_changed(current: int) -> void:
	if not _current(current): return
	await open_season(selected_season)
	if _current(current + 1) and not selected_season.is_empty():
		watched_control.button.grab_focus()

func _show_seasons() -> void:
	selected_season = {}
	generation += 1
	episode_section.hide()
	navigation.hide()
	season_section.show()
	section_changed.emit()
	load_seasons()
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
