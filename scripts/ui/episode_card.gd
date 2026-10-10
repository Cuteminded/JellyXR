class_name EpisodeCard
extends PanelContainer

signal chosen(item: Dictionary)

var item: Dictionary
var artwork: ArtworkLoader
var play_button: Button
var thumbnail: TextureRect
var title_label: Label

func _ready() -> void:
	add_theme_stylebox_override("panel", Widgets.surface(Color("162133"), 14, 18))
	var row := BoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	add_child(row)
	row.vertical = size.x < 740
	resized.connect(func(): row.vertical = size.x < 740)
	var image_column := VBoxContainer.new()
	image_column.add_theme_constant_override("separation", 12)
	image_column.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	image_column.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(image_column)
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(240, 135)
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	frame.add_theme_stylebox_override("panel", Widgets.surface(Color("25334a"), 10))
	image_column.add_child(frame)
	var fallback := Widgets.label("No preview available", frame, 20)
	fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	thumbnail = TextureRect.new()
	thumbnail.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumbnail.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	thumbnail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(thumbnail)
	artwork.fetch(thumbnail, item)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 12)
	row.add_child(text)
	title_label = _label("%s. %s" % [item.get("IndexNumber", "?"), item.get("Name", "Episode")], text, 26)
	var facts := DetailsMetadata.facts(item)
	var user: Dictionary = item.get("UserData", {}) if item.get("UserData") else {}
	var position := int(user.get("PlaybackPositionTicks", 0))
	if position > 0: facts.append("Continue from " + DetailsMetadata.duration(position))
	if not facts.is_empty():
		_label("  /  ".join(facts), text, 20).add_theme_color_override("font_color", Color("b0bbce"))
	_label(str(item.get("Overview") if item.get("Overview") else "No description available."), text, 22)
	play_button = Widgets.button("Resume episode" if position > 0 else "Play episode", func(): chosen.emit(item), image_column)
	play_button.custom_minimum_size = Vector2(190, 56)
	play_button.accessibility_name = play_button.text + " " + str(item.get("Name", "Episode"))

func _label(value: String, parent: Node, font_size: int) -> Label:
	var label := Widgets.label(value, parent, font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_constant_override("line_spacing", 5)
	return label
