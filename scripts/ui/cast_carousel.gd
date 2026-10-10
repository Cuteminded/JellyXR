class_name CastCarousel
extends VBoxContainer

var people: Array = []
var artwork: ArtworkLoader
var scroll: ScrollContainer
var cards: HBoxContainer
var previous_button: Button
var next_button: Button

const PORTRAIT_SIZE := Vector2(180, 270)
const CARD_SPACING := 18

func _ready() -> void:
	add_theme_constant_override("separation", 18)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 12)
	add_child(heading)
	var title := Widgets.label("Cast & crew", heading, 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	previous_button = Widgets.button("<", _move.bind(-1), heading)
	next_button = Widgets.button(">", _move.bind(1), heading)
	for button in [previous_button, next_button]:
		button.custom_minimum_size = Vector2(64, 56)
	previous_button.accessibility_name = "Previous cast members"
	previous_button.tooltip_text = "Previous cast members"
	next_button.accessibility_name = "Next cast members"
	next_button.tooltip_text = "Next cast members"
	scroll = ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.custom_minimum_size.y = 360
	scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scroll)
	cards = HBoxContainer.new()
	cards.add_theme_constant_override("separation", CARD_SPACING)
	scroll.add_child(cards)
	for person in people:
		if person.get("Name"): _add_person(person)
	var bar := scroll.get_h_scroll_bar()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.value_changed.connect(func(_value: float): _update_navigation())
	bar.changed.connect(func(): _update_navigation.call_deferred())
	_update_navigation.call_deferred()

func _add_person(person: Dictionary) -> void:
	var card := VBoxContainer.new()
	card.custom_minimum_size.x = PORTRAIT_SIZE.x
	card.add_theme_constant_override("separation", 8)
	cards.add_child(card)
	var frame := PanelContainer.new()
	frame.custom_minimum_size = PORTRAIT_SIZE
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	frame.add_theme_stylebox_override("panel", Widgets.surface(Color("25334a"), 12))
	card.add_child(frame)
	var fallback := Widgets.label(str(person.Name).left(1).to_upper(), frame, 48)
	fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fallback.add_theme_color_override("font_color", Color("b0bbce"))
	var portrait := TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.accessibility_name = "Portrait of " + str(person.Name)
	frame.add_child(portrait)
	if person.get("Id"):
		var image_item := person.duplicate()
		if person.get("PrimaryImageTag"):
			image_item["ImageTags"] = {"Primary": person.PrimaryImageTag}
		artwork.fetch(portrait, image_item)
	_caption(str(person.Name), card, 22)
	var role := str(person.get("Role") if person.get("Role") else person.get("Type", ""))
	if not role.is_empty():
		_caption(role, card, 20).add_theme_color_override("font_color", Color("b0bbce"))

func _caption(value: String, parent: Node, font_size: int) -> Label:
	var label := Widgets.label(value, parent, font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_constant_override("line_spacing", 3)
	return label

func _move(direction: int) -> void:
	scroll.scroll_horizontal += int(direction * maxf(PORTRAIT_SIZE.x + CARD_SPACING, scroll.size.x - PORTRAIT_SIZE.x - CARD_SPACING))

func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed: return
	if event.button_index not in [MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]: return
	var direction := 1 if event.button_index == MOUSE_BUTTON_WHEEL_RIGHT else -1
	scroll.scroll_horizontal += int(direction * maxf(1.0, event.factor * 80))
	accept_event()

func _update_navigation() -> void:
	var bar := scroll.get_h_scroll_bar()
	previous_button.disabled = bar.value <= bar.min_value
	next_button.disabled = bar.value >= bar.max_value - bar.page
