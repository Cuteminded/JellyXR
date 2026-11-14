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
var favourite_control: VBoxContainer
var resume_label: Label
var resume_progress: ProgressBar
var back_button: Button
var title_label: Label
var overview_label: Label
var poster: TextureRect
var backdrop: TextureRect
var cast_carousel: CastCarousel
var series_playback_status: Label
var series_playback_loading := false
var movie_parts_view: MoviePartsView
var extras_view: VBoxContainer

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
	if item.get("Type", "") in ["Movie", "Series", "MusicVideo"]:
		extras_view = preload("res://scripts/ui/extras_view.gd").new()
		extras_view.api = api
		extras_view.artwork = artwork
		extras_view.item_id = str(item.Id)
		extras_view.return_item = item
		extras_view.play_requested.connect(func(extra: Dictionary): play_requested.emit(extra))
		extras_view.version_requested.connect(func(extra: Dictionary): version_requested.emit(extra))
		body.add_child(extras_view)
	_build_people()

func _build_header() -> void:
	var hero := PanelContainer.new()
	hero.add_theme_stylebox_override("panel", Widgets.surface(Color("131e2b"), 18))
	body.add_child(hero)
	backdrop = _image(hero)
	artwork.fetch(backdrop, item, true)
	_add_backdrop_fade(hero, Vector2.RIGHT, [0.95, 0.85, 0.62])
	_add_backdrop_fade(hero, Vector2.DOWN, [0.0, 0.12, 0.85])
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	hero.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 32)
	margin.add_child(row)
	_build_poster(row)
	var summary := VBoxContainer.new()
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	summary.add_theme_constant_override("separation", 12)
	row.add_child(summary)
	title_label = _wrapped(DetailsMetadata.title(item), summary, 46)
	_build_header_metadata(summary)
	_build_playback(summary)
	_build_title_actions(summary)

func _add_backdrop_fade(parent: Control, direction: Vector2, opacity: Array[float]) -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.62, 1.0])
	var colors := PackedColorArray()
	for alpha in opacity:
		var shade_color := Color("101624")
		shade_color.a = alpha
		colors.append(shade_color)
	gradient.colors = colors
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_to = direction
	var shade := _image(parent)
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.texture = texture

func _build_poster(row: HBoxContainer) -> void:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(220, 330)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var frame_style := Widgets.surface(Color("25334a"), 12)
	frame_style.set_border_width_all(1)
	frame_style.border_color = Color(1, 1, 1, 0.15)
	frame_style.shadow_color = Color(0, 0, 0, 0.45)
	frame_style.shadow_size = 12
	frame_style.shadow_offset = Vector2(0, 6)
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

func _build_header_metadata(summary: VBoxContainer) -> void:
	var values := DetailsMetadata.facts(item)
	var facts := HFlowContainer.new()
	facts.add_theme_constant_override("h_separation", 18)
	facts.add_theme_constant_override("v_separation", 4)
	summary.add_child(facts)
	for fact in values:
		var label := Widgets.label(fact, facts, 20)
		label.add_theme_color_override("font_color", Color("c2cbd9"))
	facts.visible = not values.is_empty()
	var genres: Array = item.get("Genres", []) if item.get("Genres") else []
	if not genres.is_empty(): _muted(", ".join(genres), summary, 20)
	var taglines: Array = item.get("Taglines", []) if item.get("Taglines") else []
	if not taglines.is_empty(): _wrapped(str(taglines[0]), summary, 22)

func _build_playback(parent: VBoxContainer) -> void:
	var is_series: bool = item.get("Type", "") == "Series"
	var user: Dictionary = item.get("UserData", {}) if item.get("UserData") else {}
	var position := int(user.get("PlaybackPositionTicks", 0))
	var actions := _action_row(parent)
	play_button = Widgets.button("Play series" if is_series else ("Resume" if position > 0 else "Play movie"), _play_item, actions)
	play_button.custom_minimum_size = Vector2(160, 60)
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
		play_from_start_button.custom_minimum_size.y = 60
		_build_resume_status(parent, position)

func _build_resume_status(parent: VBoxContainer, position: int) -> void:
	var status := _action_row(parent)
	resume_label = Widgets.label("Continue from " + DetailsMetadata.duration(position), status, 19)
	resume_label.add_theme_color_override("font_color", Color("c2cbd9"))
	var runtime := int(item.get("RunTimeTicks", 0) if item.get("RunTimeTicks") else 0)
	if runtime <= 0: return
	resume_progress = ProgressBar.new()
	resume_progress.show_percentage = false
	resume_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	resume_progress.custom_minimum_size = Vector2(128, 5)
	resume_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	resume_progress.add_theme_stylebox_override("background", Widgets.surface(Color("425165"), 3))
	resume_progress.add_theme_stylebox_override("fill", Widgets.surface(Color("6de3cf"), 3))
	resume_progress.value = 100.0 * float(position) / runtime
	status.add_child(resume_progress)

func _build_title_actions(parent: VBoxContainer) -> void:
	var actions := _action_row(parent)
	var type := str(item.get("Type", ""))
	if type in ["Movie", "Episode"]:
		watched_control = preload("res://scripts/ui/watched_control.gd").new()
		watched_control.api = api
		watched_control.item = item
		watched_control.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		watched_control.changed.connect(_refresh_playback_state)
		actions.add_child(watched_control)
		watched_control.button.add_theme_font_size_override("font_size", 19)
	if type in ["Movie", "Series", "Video", "MusicVideo"]:
		favourite_control = preload("res://scripts/ui/favourite_control.gd").new()
		favourite_control.api = api
		favourite_control.item = item
		favourite_control.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		actions.add_child(favourite_control)
		favourite_control.button.add_theme_font_size_override("font_size", 19)
	var sources: Array = item.get("MediaSources", []) if item.get("MediaSources") else []
	if type != "Series" and sources.size() > 1:
		version_button = Widgets.button("Choose version", func(): version_requested.emit(item), actions)
		version_button.add_theme_font_size_override("font_size", 19)
		version_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	actions.visible = actions.get_child_count() > 0

func _action_row(parent: Control) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 12)
	row.add_theme_constant_override("v_separation", 10)
	parent.add_child(row)
	return row

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
	if is_instance_valid(resume_progress):
		resume_progress.visible = position > 0
		resume_progress.value = 100.0 * float(position) / int(item.RunTimeTicks)

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
