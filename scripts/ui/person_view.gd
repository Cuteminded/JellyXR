extends LibraryView

signal back_requested

var person: Dictionary
var excluded_title_id := ""
var back_button: Button

func _ready() -> void:
	library_id = str(person.Id)
	library_name = ""
	show_hero = false
	search_row = HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 12)
	add_child(search_row)
	back_button = Widgets.button("Back to title", back_requested.emit, search_row)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 20)
	add_child(header)
	var portrait := _add_portrait(header)
	var name_label := Widgets.label(str(person.Name), header, 38)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var message := Label.new()
	message.add_theme_font_size_override("font_size", 18)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.connect(func(value: String): message.text = value)
	loading_changed.connect(func(loading: bool):
		if loading: message.text = "Loading titles...")
	super._ready()
	add_child(message)
	artwork.fetch_person(portrait, person)
	field.placeholder_text = "Search credits"

func _add_portrait(parent: Control) -> TextureRect:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(84, 112)
	frame.add_theme_stylebox_override("panel", Widgets.surface(Color("25334a"), 10))
	parent.add_child(frame)
	var initial := Widgets.label(str(person.Name).left(1).to_upper(), frame, 32)
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var portrait := TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(portrait)
	return portrait

func _fetch_page() -> Dictionary:
	return await api.person_titles(str(person.Id), excluded_title_id, search, offset)
