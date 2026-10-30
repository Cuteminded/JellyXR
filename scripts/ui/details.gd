class_name DetailsView
extends VBoxContainer

signal play_requested(item: Dictionary)
signal play_from_start_requested(item: Dictionary)
signal version_requested(item: Dictionary)
signal back_requested

var item: Dictionary
var api: JellyfinClient
var initial_season: Dictionary = {}
var artwork: ArtworkLoader
var scroll: ScrollContainer
var body: VBoxContainer
var series_browser: SeriesBrowser
var play_button: Button
var play_from_start_button: Button
var version_button: Button
var watched_control: VBoxContainer
var resume_label: Label
var back_button: Button
var title_label: Label
var overview_label: Label
var poster: TextureRect
var backdrop: TextureRect
var cast_carousel: CastCarousel
var series_playback_status: Label
var series_playback_loading := false
var movie_parts_view: MoviePartsView

func _ready() -> void:
	add_theme_constant_override("separation", 18)
	if artwork == null:
		artwork = ArtworkLoader.new()
		artwork.api = api
		add_child(artwork)
	var navigation := HBoxContainer.new()
	navigation.add_theme_constant_override("separation", 12)
	add_child(navigation)
	back_button = Widgets.button("Back to library", func(): back_requested.emit(), navigation)
	back_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 28)
	scroll.add_child(body)
	_build_header()
	if MovieParts.is_multipart(item):
		movie_parts_view = MoviePartsView.new()
		movie_parts_view.api = api
		movie_parts_view.item = item
		movie_parts_view.play_requested.connect(func(part: Dictionary): play_requested.emit(part))
		body.add_child(movie_parts_view)
	_build_information()
	if item.get("Type", "") == "Series":
		series_browser = SeriesBrowser.new()
		series_browser.api = api
		series_browser.artwork = artwork
		series_browser.series_id = str(item.Id)
		series_browser.series_item = item
		series_browser.navigation_host = navigation
		series_browser.selected_season = initial_season
		series_browser.play_requested.connect(func(episode: Dictionary): play_requested.emit(episode))
		series_browser.version_requested.connect(func(episode: Dictionary): version_requested.emit(episode))
		series_browser.section_changed.connect(_scroll_to_series)
		body.add_child(series_browser)
	_build_people()

func _build_header() -> void:
	var hero := PanelContainer.new()
	hero.add_theme_stylebox_override("panel", Widgets.surface(Color("162133"), 18))
	body.add_child(hero)
	backdrop = _image(hero)
	artwork.fetch(backdrop, item, true)
	var shade := _image(hero)
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(0.04, 0.065, 0.10, 0.97), Color(0.04, 0.065, 0.10, 0.82)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	shade.texture = texture
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	hero.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	margin.add_child(row)
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(230, 345)
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var frame_style := Widgets.surface(Color("25334a"), 12)
	frame_style.set_border_width_all(1)
	frame_style.border_color = Color(1, 1, 1, 0.15)
	frame.add_theme_stylebox_override("panel", frame_style)
	row.add_child(frame)
	frame.visible = size.x >= 760
	resized.connect(func(): frame.visible = size.x >= 760)
	var fallback := Widgets.label("No poster available", frame, 20)
	fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	poster = _image(frame)
	poster.accessibility_name = "Poster for " + str(item.get("Name", "Untitled"))
	artwork.fetch(poster, item)
	var summary := VBoxContainer.new()
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.add_theme_constant_override("separation", 16)
	row.add_child(summary)
	_muted("TV series" if item.get("Type", "") == "Series" else "Movie", summary, 20)
	title_label = _wrapped(DetailsMetadata.title(item), summary, 42)
	var facts := HFlowContainer.new()
	facts.add_theme_constant_override("h_separation", 10)
	facts.add_theme_constant_override("v_separation", 10)
	summary.add_child(facts)
	for fact in DetailsMetadata.facts(item):
		var badge := PanelContainer.new()
		badge.add_theme_stylebox_override("panel", Widgets.surface(Color("202a3d"), 8, 10))
		facts.add_child(badge)
		Widgets.label(fact, badge, 20)
	var genres: Array = item.get("Genres", []) if item.get("Genres") else []
	if not genres.is_empty(): _muted(" / ".join(genres), summary)
	var taglines: Array = item.get("Taglines", []) if item.get("Taglines") else []
	if not taglines.is_empty(): _wrapped(str(taglines[0]), summary, 24)
	_build_playback(summary)

func _build_playback(parent: VBoxContainer) -> void:
	var is_series: bool = item.get("Type", "") == "Series"
	var user: Dictionary = item.get("UserData", {}) if item.get("UserData") else {}
	var position := int(user.get("PlaybackPositionTicks", 0))
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 12)
	actions.add_theme_constant_override("v_separation", 12)
	parent.add_child(actions)
	play_button = Widgets.button("Play series" if is_series else ("Resume" if position > 0 else "Play movie"), _play_item, actions)
	play_button.custom_minimum_size = Vector2(200, 64)
	play_button.icon = preload("res://assets/icons/material/play_arrow.svg")
	play_button.add_theme_constant_override("icon_max_width", 28)
	play_button.add_theme_constant_override("h_separation", 12)
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		play_button.add_theme_color_override(state, Color("071c20"))
	Widgets.accent(play_button)
	var focus := Widgets.surface(Color("6de3cf"), 12, 16)
	focus.set_border_width_all(3)
	focus.border_color = Color("071c20")
	play_button.add_theme_stylebox_override("focus", focus)
	if is_series:
		play_button.tooltip_text = "Start the first episode or continue where you left off."
		series_playback_status = _muted("", parent, 20)
		series_playback_status.hide()
		return
	if position > 0:
		play_from_start_button = Widgets.button("Play from start", func(): play_from_start_requested.emit(item), actions)
		play_from_start_button.custom_minimum_size = Vector2(200, 64)
		resume_label = _muted("Continue from " + DetailsMetadata.duration(position), parent, 20)
	var secondary_actions := HFlowContainer.new()
	secondary_actions.add_theme_constant_override("h_separation", 12)
	secondary_actions.add_theme_constant_override("v_separation", 12)
	parent.add_child(secondary_actions)
	if item.get("Type", "") in ["Movie", "Episode"]:
		watched_control = preload("res://scripts/ui/watched_control.gd").new()
		watched_control.api = api
		watched_control.item = item
		watched_control.changed.connect(_refresh_playback_state)
		secondary_actions.add_child(watched_control)
		watched_control.button.custom_minimum_size.y = 64
	var sources: Array = item.get("MediaSources", []) if item.get("MediaSources") else []
	if sources.size() > 1:
		version_button = Widgets.button("Choose version", func(): version_requested.emit(item), secondary_actions)
		version_button.custom_minimum_size = Vector2(200, 64)
		version_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

func _play_item() -> void:
	if item.get("Type", "") != "Series":
		play_requested.emit(item)
		return
	if series_playback_loading: return
	series_playback_loading = true
	play_button.disabled = true
	play_button.text = "Loading episode..."
	series_playback_status.hide()
	var result := await api.series_playback(str(item.Id))
	if not is_inside_tree(): return
	series_playback_loading = false
	play_button.disabled = false
	play_button.text = "Play series"
	if not result.ok:
		series_playback_status.text = "Could not load an episode. Try again."
		series_playback_status.show()
		return
	var episodes: Array = result.data.get("Items", [])
	if episodes.is_empty():
		series_playback_status.text = "No episodes available for this series."
		series_playback_status.show()
		return
	var episode: Dictionary = episodes[0].duplicate(true)
	episode["Type"] = "Episode"
	episode["SeriesId"] = str(item.Id)
	play_requested.emit(episode)

func _refresh_playback_state() -> void:
	var position := int(item.UserData.get("PlaybackPositionTicks", 0))
	play_button.text = "Resume" if position > 0 else ("Play episode" if item.get("Type") == "Episode" else "Play movie")
	if is_instance_valid(play_from_start_button): play_from_start_button.visible = position > 0
	if is_instance_valid(resume_label):
		resume_label.visible = position > 0
		resume_label.text = "Continue from " + DetailsMetadata.duration(position)

func _build_information() -> void:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 14)
	body.add_child(section)
	Widgets.label("Overview", section, 28)
	overview_label = _wrapped(str(item.get("Overview") if item.get("Overview") else "No description available."), section)
	overview_label.add_theme_constant_override("line_spacing", 7)
	var media := DetailsMetadata.streams(item)
	var studios: Array = item.get("Studios", []) if item.get("Studios") else []
	var studio_names: Array[String] = []
	for studio in studios:
		if studio.get("Name"): studio_names.append(str(studio.Name))
	if not studio_names.is_empty(): media["Studios"] = ", ".join(studio_names)
	if media.is_empty(): return
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 12)
	body.add_child(info)
	for key in media:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		info.add_child(row)
		var label := _muted(str(key), row, 20)
		label.custom_minimum_size.x = 90
		label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_wrapped(str(media[key]), row, 20)

func _build_people() -> void:
	var people: Array = item.get("People", []) if item.get("People") else []
	if people.is_empty(): return
	cast_carousel = CastCarousel.new()
	cast_carousel.people = people
	cast_carousel.artwork = artwork
	body.add_child(cast_carousel)

func _image(parent: Node) -> TextureRect:
	var image := TextureRect.new()
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(image)
	return image

func _scroll_to_series() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_inside_tree(): scroll.scroll_vertical = int(series_browser.position.y)

func _wrapped(text: String, parent: Node, font_size: int = 22) -> Label:
	var label := Widgets.label(text, parent, font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _muted(text: String, parent: Node, font_size: int = 22) -> Label:
	var label := _wrapped(text, parent, font_size)
	label.add_theme_color_override("font_color", Color("b0bbce"))
	return label
