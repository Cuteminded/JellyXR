extends SceneTree

class FixtureArtwork extends ArtworkLoader:
	var fetched: Array = []
	func fetch(target: TextureRect, item: Dictionary, _backdrop: bool = false) -> void:
		if not item.get("ImageTags", {}).has("Primary"): return
		fetched.append(item)
		var texture := GradientTexture2D.new()
		var gradient := Gradient.new()
		gradient.colors = PackedColorArray([Color("574c78"), Color("25334a")])
		texture.gradient = gradient
		target.texture = texture

var failures := 0

func _initialize() -> void:
	call_deferred("run_checks")

func settle() -> void:
	for frame in range(8): await process_frame

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func run_checks() -> void:
	root.size = Vector2i(1536, 960)
	var shell := UiShell.new()
	root.add_child(shell)
	shell.set_signed_in(true)
	shell.select("movies", "Movies")
	var artwork := FixtureArtwork.new()
	root.add_child(artwork)
	var people: Array = []
	for index in range(12):
		people.append({"Id": str(index), "Name": "Cast member %d" % index, "Role": "Character %d" % index, "PrimaryImageTag": "portrait-tag" if index == 0 else ""})
	people[1].Name = "A performer with a very long full name"
	people[1].Role = "A character with a long name that must remain fully readable"
	people.append({"Id": "unnamed"})
	var view := DetailsView.new()
	view.api = JellyfinClient.new()
	view.add_child(view.api)
	view.artwork = artwork
	view.item = {"Id": "movie", "Type": "Movie", "Name": "Movie details", "People": people}
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.page.add_child(view)
	await settle()
	var cast := view.cast_carousel
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 400
	view.body.add_child(spacer)
	await settle()
	check(cast.cards.get_child_count() == 12, "Each named person must have one portrait card.")
	check(artwork.fetched.size() == 1 and artwork.fetched[0].ImageTags.Primary == "portrait-tag", "Jellyfin person image tags must load portraits by person ID.")
	check(cast.cards.get_child(0).get_child(0).get_child(1).texture != null, "Available portraits must appear in their cards.")
	check(cast.previous_button.disabled and not cast.next_button.disabled, "Only forward navigation should be available at the start.")
	check(not cast.scroll.get_h_scroll_bar().visible, "The cast scrollbar must stay hidden.")
	var outer_position := view.scroll.scroll_vertical
	cast.next_button.pressed.emit()
	await settle()
	check(cast.scroll.scroll_horizontal > 0 and not cast.previous_button.disabled, "Next must scroll the row horizontally.")
	check(view.scroll.scroll_vertical == outer_position, "Carousel navigation must preserve the main page's scroll position.")
	cast.scroll.scroll_horizontal = 0
	view.scroll.ensure_control_visible(cast)
	await settle()
	for direction in [MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_UP]:
		var position := view.scroll.scroll_vertical
		var wheel := InputEventMouseButton.new()
		wheel.button_index = direction
		wheel.pressed = true
		wheel.position = cast.scroll.get_global_rect().position + Vector2(90, 90)
		wheel.global_position = wheel.position
		root.push_input(wheel, true)
		await settle()
		check(cast.scroll.scroll_horizontal == 0, "Vertical wheel input over a portrait must not move the cast row.")
		check(view.scroll.scroll_vertical > position if direction == MOUSE_BUTTON_WHEEL_DOWN else view.scroll.scroll_vertical < position, "Vertical wheel input over the cast must scroll the main page in the requested direction.")
	for direction in [MOUSE_BUTTON_WHEEL_RIGHT, MOUSE_BUTTON_WHEEL_LEFT]:
		var horizontal_position := cast.scroll.scroll_horizontal
		var vertical_position := view.scroll.scroll_vertical
		var wheel := InputEventMouseButton.new()
		wheel.button_index = direction
		wheel.pressed = true
		wheel.factor = 0.2
		wheel.position = cast.scroll.get_global_rect().position + Vector2(90, 90)
		wheel.global_position = wheel.position
		root.push_input(wheel, true)
		await settle()
		check(cast.scroll.scroll_horizontal > horizontal_position if direction == MOUSE_BUTTON_WHEEL_RIGHT else cast.scroll.scroll_horizontal < horizontal_position, "Horizontal wheel input must move the cast row in the requested direction.")
		check(view.scroll.scroll_vertical == vertical_position, "Horizontal input must not move the details page vertically.")
	cast.scroll.scroll_horizontal = 0
	await settle()
	check(cast.cards.get_child(1).get_combined_minimum_size().y <= cast.scroll.size.y, "Long names and roles must not be clipped vertically.")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://dist/cast-preview.png")
	cast.scroll.scroll_horizontal = 100000
	await settle()
	check(cast.next_button.disabled and not cast.previous_button.disabled, "Next must be disabled at the end.")
	for width in [1280, 960]:
		root.size.x = width
		await settle()
		check(cast.size.x <= view.scroll.size.x, "The carousel must fit narrower panels.")
		check(cast.cards.get_child(0).size.x == 180, "Portrait cards must retain their width while scrolling.")
	print("Cast checks: ", "PASS" if failures == 0 else str(failures) + " failures")
	quit(1 if failures else 0)
