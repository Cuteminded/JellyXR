class_name DetailsView
extends VBoxContainer

signal play_requested(item: Dictionary)
signal back_requested

var item: Dictionary
var api: JellyfinClient
var artwork: ArtworkLoader
var scroll: ScrollContainer
var body: VBoxContainer
var episode_list: VBoxContainer
var play_button: Button
var back_button: Button
var title_label: Label
var overview_label: Label
var poster: TextureRect
var backdrop: TextureRect

func _ready() -> void:
	add_theme_constant_override("separation", 18)
	if artwork == null:
		artwork = ArtworkLoader.new()
		artwork.api = api
		add_child(artwork)
	var navigation := HBoxContainer.new()
	add_child(navigation)
	back_button = Widgets.button("Back to library", func(): back_requested.emit(), navigation)
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
	_build_information()
	if item.get("Type", "") == "Series":
		Widgets.label("Episodes", body, 28)
		episode_list = VBoxContainer.new()
		episode_list.add_theme_constant_override("separation", 12)
		body.add_child(episode_list)
		Widgets.label("Loading episodes...", episode_list, 22)
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
	title_label = _wrapped(str(item.get("Name", "Untitled")), summary, 42)
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
	if item.get("Type", "") == "Series":
		_muted("Choose an episode below to start watching.", parent)
		return
	var user: Dictionary = item.get("UserData", {}) if item.get("UserData") else {}
	var position := int(user.get("PlaybackPositionTicks", 0))
	var actions := HBoxContainer.new()
	parent.add_child(actions)
	play_button = Widgets.button("Resume" if position > 0 else "Play movie", func(): play_requested.emit(item), actions)
	play_button.custom_minimum_size = Vector2(200, 64)
	play_button.icon = preload("res://assets/icons/play.svg")
	play_button.add_theme_constant_override("icon_max_width", 28)
	play_button.add_theme_constant_override("h_separation", 12)
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		play_button.add_theme_color_override(state, Color("071c20"))
	Widgets.accent(play_button)
	var focus := Widgets.surface(Color("6de3cf"), 12, 16)
	focus.set_border_width_all(3)
	focus.border_color = Color("071c20")
	play_button.add_theme_stylebox_override("focus", focus)
	if position > 0:
		_muted("Continue from " + DetailsMetadata.duration(position), parent, 20)

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
	Widgets.label("Cast & crew", body, 28)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 12)
	body.add_child(names)
	for person in people:
		if not person.get("Name"): continue
		var role := str(person.get("Role") if person.get("Role") else person.get("Type", ""))
		_wrapped(str(person.Name) + ("  /  " + role if not role.is_empty() else ""), names, 22)

func set_episodes(items: Array, error: String = "") -> void:
	for child in episode_list.get_children():
		episode_list.remove_child(child)
		child.queue_free()
	if not error.is_empty():
		_wrapped(error, episode_list)
		return
	if items.is_empty():
		_muted("No episodes available.", episode_list)
	for episode in items:
		var button := Widgets.button("S%s E%s  %s" % [episode.get("ParentIndexNumber", "?"), episode.get("IndexNumber", "?"), episode.get("Name", "Episode")], func(): play_requested.emit(episode), episode_list)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _image(parent: Node) -> TextureRect:
	var image := TextureRect.new()
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(image)
	return image

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
