extends SceneTree

class FixtureSettings extends JellyframeSettings:
	var saves := 0
	func save(_path: String = PATH) -> Error:
		saves += 1
		return OK

class FixtureApi extends JellyfinClient:
	var requests: Array[String] = []
	func request(path: String, _method: HTTPClient.Method = HTTPClient.METHOD_GET, _body: Dictionary = {}) -> Dictionary:
		requests.append(path)
		var values := {}
		for pair in path.split("?")[1].split("&"):
			var parts := pair.split("=")
			values[parts[0]] = parts[1].uri_decode()
		var items := []
		if values.has("Ids"):
			for id in str(values.Ids).split(","):
				items.push_front({"Id": id, "Name": "Movie " + id})
		elif values.get("SortBy") == "Random":
			for index in range(52): items.append({"Id": str(51 - index)})
		return {"ok": true, "data": {"Items": items, "TotalRecordCount": 52}}

var failures := 0

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func run_checks() -> void:
	var settings := JellyframeSettings.new()
	settings.device_id = "test-device"
	settings.library_sort_by = "PremiereDate"
	settings.library_sort_order = "Descending"
	settings.environment = "Passthrough"
	settings.playback_mode = "original"
	settings.transcode_resolution = 2160
	var path := "res://dist/settings-test.cfg"
	check(settings.save(path) == OK, "Settings can be saved.")
	var restored := JellyframeSettings.new()
	restored.load_settings(path)
	check(restored.library_sort_by == "PremiereDate" and restored.library_sort_order == "Descending", "Sorting survives a restart.")
	check(restored.environment == "Passthrough", "Passthrough preference survives a restart.")
	check(restored.playback_mode == "original", "Playback preference survives a restart.")
	check(restored.transcode_resolution == 2160, "Transcoded 4K preference survives a restart.")
	var config := ConfigFile.new()
	config.load(path)
	config.set_value("library", "sort_by", "Invalid")
	config.set_value("library", "sort_order", "Invalid")
	config.set_value("screen", "environment", "Invalid")
	config.set_value("playback", "mode", "Invalid")
	config.set_value("playback", "transcode_resolution", 999)
	config.save(path)
	restored.load_settings(path)
	check(restored.library_sort_by == "SortName" and restored.library_sort_order == "Ascending", "Invalid sorting preferences use safe defaults.")
	check(restored.environment == "Void", "Invalid environments fall back to Void.")
	check(restored.playback_mode == "auto", "Invalid playback preferences fall back to Automatic.")
	check(restored.transcode_resolution == 1080, "Invalid conversion resolutions fall back to 1080p.")
	config.erase_section_key("playback", "transcode_resolution")
	config.save(path)
	restored.load_settings(path)
	check(restored.transcode_resolution == 1080, "Existing settings without a resolution keep the previous 1080p quality.")
	for names in [["Theatre", "Cinema"], ["Theatre LowRes", "Theatre"]]:
		if config.has_section_key("screen", "environment_version"):
			config.erase_section_key("screen", "environment_version")
		config.set_value("screen", "environment", names[0])
		check(config.save(path) == OK, "Legacy environment fixture can be saved.")
		restored.load_settings(path)
		check(restored.environment == names[1], "Renaming preserves the selected legacy environment.")
		check(restored.save(path) == OK, "Migrated environment can be saved.")
		restored.load_settings(path)
		check(restored.environment == names[1], "Migrated environment names stay stable after another restart.")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var api := FixtureApi.new()
	root.add_child(api)
	api.library_sort_by = "PremiereDate"
	api.library_sort_order = "Descending"
	await api.library("", 0, "movies")
	check("SortBy=PremiereDate" in api.requests.back() and "SortOrder=Descending" in api.requests.back(), "Libraries send the saved sort field and order.")
	await api.library()
	check("SortBy=DateCreated" in api.requests.back() and "SortOrder=Descending" in api.requests.back(), "Home stays sorted by newest additions.")
	api.library_sort_by = "Random"
	var first := await api.library("", 0, "movies")
	var second := await api.library("", 25, "movies")
	var last := await api.library("", 50, "movies")
	var ids := []
	for result in [first, second, last]:
		for item in result.data.Items: ids.append(item.Id)
	var expected := []
	for index in range(52): expected.append(str(51 - index))
	check(ids == expected, "Random pages preserve the original shuffled sequence without repeats or omissions.")
	check(api.requests.size() == 6, "Random scrolling reuses one catalog snapshot.")
	api.queue_free()
	var shell := UiShell.new()
	root.add_child(shell)
	shell.set_signed_in(true)
	shell.heading.text = "Settings"
	var view := SettingsView.new()
	var fixture := FixtureSettings.new()
	view.settings = fixture
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.page.add_child(view)
	await process_frame
	var release_date: CheckBox = view.sort_choices.get_child(8)
	release_date.button_pressed = true
	release_date.pressed.emit()
	check(fixture.library_sort_by == "PremiereDate" and fixture.saves == 1, "Selecting a sort field updates and saves the preference.")
	var descending: CheckBox = view.sections[0].get_child(2).get_child(1)
	descending.button_pressed = true
	descending.pressed.emit()
	check(fixture.library_sort_order == "Descending" and fixture.saves == 2, "Selecting sort order updates and saves the preference.")
	check(view.sections[0].visible and not view.sections[1].visible, "Library sorting is the default section.")
	if "--capture" in OS.get_cmdline_user_args():
		await capture("settings-library")
	var screen_tab: Button = view.get_child(0).get_child(1)
	screen_tab.button_pressed = true
	screen_tab.pressed.emit()
	check(not view.sections[0].visible and view.sections[1].visible, "Screen settings are reachable through the section selector.")
	var changes := []
	view.screen_changed.connect(func(): changes.append("screen"))
	var width_slider: HSlider = view.screen_dimensions.get_child(0).get_child(1)
	width_slider.value = 4.0
	check(is_equal_approx(fixture.width, 4.0) and changes == ["screen"] and fixture.saves == 3, "Screen adjustments apply and save from keyboard or pointer input.")
	fixture.distance = 6.0
	fixture.height = 1.0
	fixture.curvature = 0.8
	fixture.environment = "Cinema"
	fixture.server = "https://example.com"
	var half_sbs: CheckBox = view.stereo_choices.get_child(1)
	half_sbs.button_pressed = true
	half_sbs.pressed.emit()
	var reset: Button = view.reset_screen_button
	reset.pressed.emit()
	check(is_equal_approx(fixture.width, 3.6) and is_equal_approx(fixture.distance, 3.0) and fixture.height == 0.0 and fixture.curvature == 0.0 and fixture.environment == "Cinema", "Reset restores screen defaults while preserving the separate environment selection.")
	check(fixture.library_sort_by == "PremiereDate" and fixture.library_sort_order == "Descending" and fixture.server == "https://example.com", "Screen reset preserves library and connection preferences.")
	check(fixture.saves == 4 and changes == ["screen", "screen"], "Reset applies immediately and saves once.")
	var restored_slider: HSlider = view.screen_dimensions.get_child(0).get_child(1)
	var restored_format: CheckBox = view.stereo_choices.get_child(1)
	check(is_equal_approx(restored_slider.value, 3.6) and restored_format.button_pressed, "Reset updates displayed values and preserves the current video format.")
	if "--capture" in OS.get_cmdline_user_args():
		await capture("settings-screen")
	var environment_tab: Button = view.get_child(0).get_child(2)
	environment_tab.button_pressed = true
	environment_tab.pressed.emit()
	check(view.sections[2].visible and not view.sections[1].visible, "Environment has its own settings page.")
	var theatre_choice: CheckBox = view.sections[2].get_child(2).get_child(1)
	theatre_choice.button_pressed = true
	theatre_choice.pressed.emit()
	var theatre_slider: HSlider = view.screen_dimensions.get_child(0).get_child(1)
	check(not theatre_slider.editable, "Fixed Theatre projection disables Void screen positioning.")
	var low_res_choice: CheckBox = view.sections[2].get_child(2).get_child(2)
	low_res_choice.button_pressed = true
	low_res_choice.pressed.emit()
	check(fixture.environment == "Theatre" and fixture.is_theatre(), "LowRes is a separate theatre option.")
	check(not (view.screen_dimensions.get_child(0).get_child(1) as HSlider).editable, "LowRes has a fixed screen.")
	var saved := JellyframeSettings.new()
	saved.device_id = "test-device"
	saved.environment = "Theatre"
	var low_res_path := "res://dist/settings-lowres-test.cfg"
	check(saved.save(low_res_path) == OK, "LowRes selection can be saved.")
	var restored_low_res := JellyframeSettings.new()
	restored_low_res.load_settings(low_res_path)
	check(restored_low_res.environment == "Theatre", "LowRes selection survives restarting the app.")
	var passthrough_choice: CheckBox = view.sections[2].get_child(2).get_child(3)
	check(passthrough_choice.disabled, "Unsupported devices cannot select Passthrough.")
	passthrough_choice.disabled = false
	passthrough_choice.button_pressed = true
	passthrough_choice.pressed.emit()
	check(fixture.environment == "Passthrough", "Passthrough selection updates the saved environment.")
	var passthrough_slider: HSlider = view.screen_dimensions.get_child(0).get_child(1)
	check(passthrough_slider.editable, "Passthrough uses adjustable screen controls.")
	theatre_choice.button_pressed = true
	theatre_choice.pressed.emit()
	passthrough_choice.disabled = true
	if "--capture" in OS.get_cmdline_user_args():
		await capture("settings-environment")
		shell.custom_minimum_size = Vector2(760, 850)
		root.size = Vector2i(800, 900)
		var library_tab: Button = view.get_child(0).get_child(0)
		library_tab.button_pressed = true
		library_tab.pressed.emit()
		await capture("settings-narrow")
		check(view.sort_choices.columns == 1, "Narrow settings use a single column.")
		check(shell.get_global_rect().end.x <= root.size.x, "Narrow settings must fit within the viewport.")
		view.scroll.scroll_vertical = 10000
		await capture("settings-narrow-bottom")
	var playback_tab: Button = view.get_child(0).get_child(3)
	playback_tab.button_pressed = true
	playback_tab.pressed.emit()
	check(view.sections[3].visible and not view.sections[2].visible, "Playback has its own settings page.")
	var original_choice: CheckBox = view.playback_choices.get_child(1).get_child(0)
	var transcoded_choice: CheckBox = view.playback_choices.get_child(2).get_child(0)
	var saves_before := fixture.saves
	original_choice.button_pressed = true
	original_choice.pressed.emit()
	check(fixture.playback_mode == "original" and fixture.saves == saves_before + 1, "Original playback selection saves once.")
	check(not view.transcode_options.visible, "Original playback hides conversion resolution choices.")
	transcoded_choice.button_pressed = true
	transcoded_choice.pressed.emit()
	check(fixture.playback_mode == "transcoded" and not original_choice.button_pressed, "Playback options are mutually exclusive.")
	check(view.transcode_options.visible and view.transcode_choices.get_child_count() == 3, "Transcoded playback shows three resolution choices.")
	check((view.transcode_choices.get_child(1) as CheckBox).button_pressed, "1080p is the default conversion resolution.")
	for sample in [[0, 720], [1, 1080], [2, 2160]]:
		var quality: CheckBox = view.transcode_choices.get_child(sample[0])
		saves_before = fixture.saves
		quality.button_pressed = true
		quality.pressed.emit()
		check(fixture.transcode_resolution == sample[1] and fixture.saves == saves_before + 1, "Choosing a resolution saves the preference once.")
	view._reset_screen()
	check(fixture.playback_mode == "transcoded" and fixture.transcode_resolution == 2160, "Screen reset preserves playback mode and conversion resolution.")
	original_choice.button_pressed = true
	original_choice.pressed.emit()
	transcoded_choice.button_pressed = true
	transcoded_choice.pressed.emit()
	check(view.transcode_options.visible and (view.transcode_choices.get_child(2) as CheckBox).button_pressed, "Returning to Transcoded keeps the chosen 4K resolution.")
	if "--capture" in OS.get_cmdline_user_args():
		await capture("settings-playback")
		view.scroll.scroll_vertical = 10000
		await capture("settings-playback-resolution")
	print("Settings failures: ", failures)
	quit(1 if failures else 0)

func capture(filename: String) -> void:
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://dist/" + filename + ".png")
