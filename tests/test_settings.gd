extends SceneTree

class FixtureSettings extends JellyXRSettings:
	var saves := 0
	var save_error := OK
	func save(_path: String = PATH) -> Error:
		saves += 1
		return save_error

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
	var settings := JellyXRSettings.new()
	check(is_equal_approx(settings.height, 0.0) and is_equal_approx(settings.screen_height_offset(), -0.2), "Zero screen height uses the lowered reference position")
	var legacy := ConfigFile.new()
	legacy.set_value("screen", "height", -0.2)
	legacy.set_value("connection", "device_id", "legacy-test-device")
	var legacy_path := "user://settings-height-reference-test.cfg"
	check(legacy.save(legacy_path) == OK, "Legacy screen height fixture can be saved")
	var migrated := JellyXRSettings.new()
	migrated.load_settings(legacy_path)
	check(is_equal_approx(migrated.height, 0.0) and is_equal_approx(migrated.screen_height_offset(), -0.2), "Existing lowered screen positions become zero without moving the screen")
	migrated.save(legacy_path)
	var reloaded := JellyXRSettings.new()
	reloaded.load_settings(legacy_path)
	check(is_equal_approx(reloaded.height, 0.0), "Reloading migrated settings does not apply the reference shift twice")
	settings.device_id = "test-device"
	settings.library_sort_by = "PremiereDate"
	settings.library_sort_order = "Descending"
	settings.environment = "Passthrough"
	check(not settings.follow_screen, "Screen following is off by default.")
	settings.follow_screen = true
	settings.playback_mode = "original"
	settings.transcode_resolution = 1440
	settings.transcode_max_fps = 60
	var path := "user://settings-test.cfg"
	check(settings.save(path) == OK, "Settings can be saved.")
	var restored := JellyXRSettings.new()
	restored.load_settings(path)
	check(restored.library_sort_by == "PremiereDate" and restored.library_sort_order == "Descending", "Sorting survives a restart.")
	check(restored.environment == "Passthrough", "Passthrough preference survives a restart.")
	check(restored.follow_screen, "Screen following survives a restart.")
	check(restored.playback_mode == "original", "Playback preference survives a restart.")
	check(restored.transcode_resolution == 1440, "The 2K transcoding preference survives a restart.")
	check(restored.transcode_max_fps == 60, "The transcoding frame rate limit survives a restart.")
	var config := ConfigFile.new()
	config.load(path)
	config.set_value("library", "sort_by", "Invalid")
	config.set_value("library", "sort_order", "Invalid")
	config.set_value("screen", "environment", "Invalid")
	config.set_value("playback", "mode", "Invalid")
	config.set_value("playback", "transcode_resolution", 999)
	config.set_value("playback", "transcode_max_fps", 999)
	config.save(path)
	restored.load_settings(path)
	check(restored.library_sort_by == "SortName" and restored.library_sort_order == "Ascending", "Invalid sorting preferences use safe defaults.")
	check(restored.environment == "Void", "Invalid environments fall back to Void.")
	check(restored.playback_mode == "auto", "Invalid playback preferences fall back to Automatic.")
	check(restored.transcode_resolution == 1080, "Invalid conversion resolutions fall back to 1080p.")
	check(restored.transcode_max_fps == 30, "Invalid frame rate limits fall back to 30 fps.")
	config.erase_section_key("playback", "transcode_resolution")
	config.erase_section_key("playback", "transcode_max_fps")
	config.erase_section_key("screen", "follow_screen")
	config.save(path)
	restored.load_settings(path)
	check(restored.transcode_resolution == 1080, "Existing settings without a resolution keep the previous 1080p quality.")
	check(restored.transcode_max_fps == 30, "Existing settings without a frame rate limit keep the 30 fps default.")
	check(not restored.follow_screen, "Existing settings without screen following keep a stationary screen.")
	config.set_value("screen", "environment_version", 1)
	for names in [["Theatre", "Theatre"], ["Theatre LowRes", "Void"], [123, "Void"]]:
		config.set_value("screen", "environment", names[0])
		check(config.save(path) == OK, "Environment fixture can be saved.")
		restored.load_settings(path)
		check(restored.environment == names[1], "Saved environments use their exact name or fall back to Void.")
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
	shell.set_settings_mode(true)
	view.navigation_host = shell.settings_navigation
	var fixture := FixtureSettings.new()
	view.settings = fixture
	var subtitle_track := SubtitleTrack.new()
	root.add_child(subtitle_track)
	view.subtitles = subtitle_track
	view.subtitle_timing_enabled = true
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.page.add_child(view)
	await process_frame
	for button in view.find_children("*", "Button", true, false):
		check(button.text != "Back", "Settings pages do not show a Back button.")
	var release_date: CheckBox = view.sort_choices.get_child(8)
	release_date.button_pressed = true
	release_date.pressed.emit()
	check(fixture.library_sort_by == "PremiereDate" and fixture.saves == 1, "Selecting a sort field updates and saves the preference.")
	var descending: CheckBox = view.sort_order_choices.get_child(1)
	descending.button_pressed = true
	descending.pressed.emit()
	check(fixture.library_sort_order == "Descending" and fixture.saves == 2, "Selecting sort order updates and saves the preference.")
	check(view.sections[0].visible and not view.sections[1].visible, "Library sorting is the default section.")
	if "--capture" in OS.get_cmdline_user_args():
		await capture("settings-library")
	var screen_tab: Button = view.navigation_buttons[1]
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
	var reset: Button = view.reset_screen_button
	reset.pressed.emit()
	check(is_equal_approx(fixture.width, 3.6) and is_equal_approx(fixture.distance, 3.0) and is_equal_approx(fixture.height, 0.0) and fixture.curvature == 0.0 and fixture.environment == "Cinema", "Reset restores screen defaults while preserving the separate environment selection.")
	check(fixture.library_sort_by == "PremiereDate" and fixture.library_sort_order == "Descending" and fixture.server == "https://example.com", "Screen reset preserves library and connection preferences.")
	check(fixture.saves == 4 and changes == ["screen", "screen"], "Reset applies immediately and saves once.")
	var restored_slider: HSlider = view.screen_dimensions.get_child(0).get_child(1)
	check(is_equal_approx(restored_slider.value, 3.6), "Reset updates displayed screen position values.")
	if "--capture" in OS.get_cmdline_user_args():
		await capture("settings-screen")
	var environment_tab: Button = view.navigation_buttons[2]
	environment_tab.button_pressed = true
	environment_tab.pressed.emit()
	check(view.sections[2].visible and not view.sections[1].visible, "Environment has its own settings page.")
	var cinema_choice: CheckBox = view.environment_buttons["Cinema"]
	cinema_choice.button_pressed = true
	cinema_choice.pressed.emit()
	var cinema_slider: HSlider = view.screen_dimensions.get_child(0).get_child(1)
	check(not cinema_slider.editable, "Fixed Cinema projection disables Void screen positioning.")
	var low_res_choice: CheckBox = view.environment_buttons["Theatre"]
	low_res_choice.button_pressed = true
	low_res_choice.pressed.emit()
	check(fixture.environment == "Theatre" and fixture.is_cinema(), "Theatre is a separate cinema option.")
	check(not (view.screen_dimensions.get_child(0).get_child(1) as HSlider).editable, "Theatre has a fixed screen.")
	var saved := JellyXRSettings.new()
	saved.device_id = "test-device"
	saved.environment = "Theatre"
	var low_res_path := "user://settings-lowres-test.cfg"
	check(saved.save(low_res_path) == OK, "Theatre selection can be saved.")
	var restored_low_res := JellyXRSettings.new()
	restored_low_res.load_settings(low_res_path)
	check(restored_low_res.environment == "Theatre", "Theatre selection survives restarting the app.")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(low_res_path))
	var passthrough_choice: CheckBox = view.environment_buttons["Passthrough"]
	check(passthrough_choice.disabled, "Unsupported devices cannot select Passthrough.")
	passthrough_choice.disabled = false
	passthrough_choice.button_pressed = true
	passthrough_choice.pressed.emit()
	check(fixture.environment == "Passthrough", "Passthrough selection updates the saved environment.")
	var passthrough_slider: HSlider = view.screen_dimensions.get_child(0).get_child(1)
	check(passthrough_slider.editable, "Passthrough uses adjustable screen controls.")
	if "--capture" in OS.get_cmdline_user_args():
		view._show_section(1)
		await process_frame
		view.scroll.scroll_vertical = 10000
		await capture("settings-screen-position")
		view._show_section(2)
	cinema_choice.button_pressed = true
	cinema_choice.pressed.emit()
	passthrough_choice.disabled = true
	if "--capture" in OS.get_cmdline_user_args():
		await capture("settings-environment")
		shell.custom_minimum_size = Vector2(760, 850)
		root.size = Vector2i(800, 900)
		var library_tab: Button = view.navigation_buttons[0]
		library_tab.button_pressed = true
		library_tab.pressed.emit()
		await capture("settings-narrow")
		check(view.sort_choices.columns == 1, "Narrow settings use a single column.")
		check(shell.get_global_rect().end.x <= root.size.x, "Narrow settings must fit within the viewport.")
		check(view.scroll.size.y >= 300, "Narrow settings leave usable space for the scrolling content.")
		check(view.navigation.get_parent() == shell.settings_navigation and not shell.libraries.visible, "Settings categories stay in the main sidebar at narrow widths.")
		view.scroll.scroll_vertical = 10000
		await capture("settings-narrow-bottom")
		for index in [1, 2, 3, 4, 5, 6]:
			view._show_section(index)
			await capture("settings-narrow-" + str(index))
			check(view.scroll.size.y >= 300 and shell.get_global_rect().end.x <= root.size.x, "Each narrow settings section remains visible and fits the window.")
		root.size = Vector2i(1440, 900)
		await process_frame
		await process_frame
	var playback_tab: Button = view.navigation_buttons[3]
	playback_tab.button_pressed = true
	playback_tab.pressed.emit()
	check(view.sections[3].visible and not view.sections[2].visible, "Playback has its own settings page.")
	var automatic_choice: CheckBox = view.playback_choices.get_child(0).get_child(0)
	var original_choice: CheckBox = view.playback_choices.get_child(1).get_child(0)
	var transcoded_choice: CheckBox = view.playback_choices.get_child(2).get_child(0)
	var saves_before := fixture.saves
	original_choice.button_pressed = true
	original_choice.pressed.emit()
	check(fixture.playback_mode == "original" and fixture.saves == saves_before + 1, "Original playback selection saves once.")
	check(view.transcode_choices.is_visible_in_tree(), "Original playback keeps the independent resolution setting visible.")
	automatic_choice.button_pressed = true
	automatic_choice.pressed.emit()
	check(fixture.playback_mode == "auto" and not original_choice.button_pressed, "Playback options are mutually exclusive.")
	check(view.transcode_choices.is_visible_in_tree() and view.transcode_choices.get_child_count() == 4, "Automatic playback shows all four resolution choices.")
	check((view.transcode_choices.get_child(1) as CheckBox).button_pressed, "1080p is the default conversion resolution.")
	for sample in [[0, 720], [1, 1080], [2, 1440], [3, 2160]]:
		var quality: CheckBox = view.transcode_choices.get_child(sample[0])
		saves_before = fixture.saves
		quality.button_pressed = true
		quality.pressed.emit()
		check(fixture.transcode_resolution == sample[1] and fixture.saves == saves_before + 1 and fixture.playback_mode == "auto", "Choosing a resolution saves it without changing Automatic mode.")
	check(view.transcode_fps_choices.is_visible_in_tree(), "Automatic playback shows the frame rate options.")
	check((view.transcode_fps_choices.get_child(2) as CheckBox).button_pressed, "30 fps is selected by default.")
	for index in JellyXRSettings.TRANSCODE_MAX_FPS_OPTIONS.size():
		var fps_choice: CheckBox = view.transcode_fps_choices.get_child(index)
		saves_before = fixture.saves
		fps_choice.button_pressed = true
		fps_choice.pressed.emit()
		check(fixture.transcode_max_fps == JellyXRSettings.TRANSCODE_MAX_FPS_OPTIONS[index] and fixture.saves == saves_before + 1, "Choosing a frame rate saves it once.")
	check(fixture.playback_mode == "auto" and fixture.transcode_resolution == 2160, "Changing the frame rate preserves the playback mode and resolution.")
	transcoded_choice.button_pressed = true
	transcoded_choice.pressed.emit()
	check(view.transcode_choices.is_visible_in_tree() and (view.transcode_choices.get_child(3) as CheckBox).button_pressed, "Switching to Transcoded keeps the chosen 4K resolution.")
	check(view.transcode_fps_choices.is_visible_in_tree() and (view.transcode_fps_choices.get_child(4) as CheckBox).button_pressed, "Switching to Transcoded keeps the chosen 60 fps limit.")
	view._reset_screen()
	check(fixture.playback_mode == "transcoded" and fixture.transcode_resolution == 2160, "Screen reset preserves playback mode and conversion resolution.")
	if "--capture" in OS.get_cmdline_user_args():
		await capture("settings-playback")
		view.scroll.scroll_vertical = 10000
		await capture("settings-playback-resolution")
	var follow_updates := []
	view.screen_follow_changed.connect(func(): follow_updates.append(true))
	var follow_saves := fixture.saves
	view.follow_switch.button_pressed = true
	check(fixture.follow_screen and fixture.saves == follow_saves + 1 and follow_updates.size() == 1, "Enabling screen following applies and saves once.")
	check(not view.follow_switch.disabled, "The shared follow switch remains available for Void when passthrough is unsupported.")
	view.follow_switch.button_pressed = false
	check(not fixture.follow_screen, "Disabling the shared switch stops screen following.")
	view._show_section(4)
	check(view.sections[4].visible and view.section_heading.text == "Subtitles", "Subtitle appearance and timing have their own main settings section")
	var size_before := fixture.subtitle_size
	var subtitle_saves := fixture.saves
	var appearance_updates := changes.size()
	for control in view.subtitle_controls.find_children("*", "Button", true, false):
		if control.accessibility_name == "Increase text size": control.pressed.emit()
		if control.accessibility_name == "Increase delay": control.pressed.emit()
	check(fixture.subtitle_size == size_before + 4 and fixture.saves == subtitle_saves + 1 and changes.size() == appearance_updates + 1, "Subtitle appearance applies immediately and saves from the main settings")
	check(subtitle_track.delay_ms == 100 and fixture.saves == subtitle_saves + 1, "Subtitle delay adjusts the active video without saving a global delay")
	var yellow: Button = view.subtitle_controls.color_buttons["Yellow"]
	yellow.button_pressed = true
	yellow.pressed.emit()
	check(fixture.subtitle_color == "Yellow", "The main settings select the subtitle color")
	var reset_timing: Button = view.subtitle_controls.get_child(view.subtitle_controls.get_child_count() - 1)
	reset_timing.pressed.emit()
	check(subtitle_track.delay_ms == 0, "Reset timing clears the active subtitle delay")
	var info_saves := fixture.saves
	view.navigation_buttons[5].pressed.emit()
	check(view.sections[5].visible and not view.sections[4].visible and view.section_heading.text == "Controls", "Controls is between Subtitles and Info")
	var controls := view.controller_controls
	check(not controls.binding_buttons.has("right_hand/menu_button") and not controls.binding_buttons.has("left_hand/menu_button"), "Menu buttons have no remapping controls")
	var binding_key := "left_hand/by_button"
	await process_frame
	await process_frame
	var controls_height := controls.size.y
	controls.binding_buttons[binding_key].pressed.emit()
	check(controls.editor.visible and controls.selected_key == binding_key, "Selecting a controller button opens its action choices")
	await process_frame
	check(is_equal_approx(controls.size.y, controls_height), "The popup does not expand the Controls page")
	check(controls.editor.get_viewport() == controls.get_viewport(), "The popup stays inside the viewport used for VR pointer input")
	controls.action_buttons["pause"].pressed.emit()
	check(not controls.editor.visible, "Choosing an action dismisses the popup")
	check(fixture.controller_bindings.action_for(binding_key) == "settings" and fixture.saves == info_saves, "Draft shortcuts do not affect active input or save before Apply")
	check(controls.draft.action_for(binding_key) == "pause" and not controls.apply_button.disabled, "Changing a shortcut enables Apply")
	check(controls.hand_views[0].action_labels[binding_key].text == "Play / pause", "The shortcut row shows the draft action")
	controls.hand_views[1].hotspots["right_hand/by_button"].pressed.emit()
	check(controls.selected_key == "right_hand/by_button", "Controller hotspots select the matching action editor")
	controls.editor.backdrop.pressed.emit()
	check(not controls.editor.visible and controls.draft.action_for(binding_key) == "pause", "Clicking outside dismisses the popup without losing pending choices")
	controls.binding_buttons[binding_key].pressed.emit()
	var cancel_popup := InputEventKey.new()
	cancel_popup.keycode = KEY_ESCAPE
	cancel_popup.pressed = true
	root.push_input(cancel_popup)
	check(not controls.editor.visible, "Escape dismisses the action popup")
	controls.apply_button.pressed.emit()
	check(fixture.controller_bindings.action_for(binding_key) == "pause" and fixture.saves == info_saves + 1, "Apply activates and saves shortcuts once")
	check(controls.apply_button.disabled and not controls.editor.visible, "Applying closes the editor and clears the pending state")
	controls.reset_button.pressed.emit()
	check(fixture.controller_bindings.action_for(binding_key) == "pause" and controls.draft.action_for(binding_key) == "settings", "Reset previews defaults until Apply")
	fixture.save_error = ERR_CANT_CREATE
	controls.apply_button.pressed.emit()
	check(controls.save_failed and not controls.apply_button.disabled, "A failed save keeps Apply available for retry")
	fixture.save_error = OK
	controls.apply_button.pressed.emit()
	check(fixture.controller_bindings.action_for(binding_key) == "settings" and not controls.save_failed and controls.apply_button.disabled, "Retry saves the restored defaults")
	info_saves = fixture.saves
	if "--capture-controls" in OS.get_cmdline_user_args():
		root.size = Vector2i(1536, 960)
		await capture("settings-controls-vr")
	if "--capture" in OS.get_cmdline_user_args():
		await capture("settings-controls")
		controls.binding_buttons[binding_key].pressed.emit()
		await capture("settings-controls-choices")
		root.size = Vector2i(800, 900)
		await capture("settings-controls-popup-narrow")
		check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(controls.editor.panel.get_rect()), "The popup fits inside a narrow viewport")
		root.size = Vector2i(1440, 900)
	view.navigation_buttons[6].pressed.emit()
	check(not controls.editor.visible, "Leaving Controls dismisses its popup")
	check(view.sections[6].visible and not view.sections[5].visible and view.section_heading.text == "Info", "Info is reachable from the settings sidebar")
	var info_text: Array[String] = []
	for label in view.sections[6].find_children("*", "Label", true, false):
		info_text.append(label.text)
	check(str(ProjectSettings.get_setting("application/config/version")) in info_text, "Info shows the configured app version")
	check(OS.get_name() in info_text and Engine.get_architecture_name() in info_text, "Info shows the running platform and architecture")
	check("Hardware video decoding" in info_text and "Startup check" in info_text and "Current playback" in info_text,
		"Info shows separate startup and playback decoder statuses")
	view._refresh_decoder_summary("d3d11va reports support at 1920 x 1080 for H.264 High, HEVC Main 10.")
	check(view.hardware_labels["Startup check"].text == "Direct3D 11"
		and view.decoder_codecs.get_child_count() == 2, "Decoder results show a backend and a badge for each codec")
	view._refresh_decoder_summary("Hardware decoder information is unavailable.")
	check(not view.decoder_codecs.visible, "Unavailable decoder results clear the codec badges")
	check(("Debug" if OS.is_debug_build() else "Release") in info_text, "Info identifies the running build type")
	check(fixture.saves == info_saves, "Opening Info does not save settings")
	check(view.hardware_labels["Headset"].text == "N/A" and view.hardware_labels["Left controller"].text == "N/A" and view.hardware_labels["Right controller"].text == "N/A", "Undetected VR hardware shows N/A")
	var controller := XRControllerTracker.new()
	controller.name = "left_hand"
	controller.profile = "/interaction_profiles/oculus/touch_controller"
	XRServer.add_tracker(controller)
	view._refresh_hardware_info()
	check(view.hardware_labels["Left controller"].text == "Oculus Touch Controller" and view.hardware_labels["Right controller"].text == "N/A", "Controller profiles appear independently for each hand")
	controller.profile = "/interaction_profiles/none"
	view._refresh_hardware_info()
	check(view.hardware_labels["Left controller"].text == "N/A", "An inactive controller profile shows N/A")
	XRServer.remove_tracker(controller)
	view._refresh_hardware_info()
	check(view.hardware_labels["Left controller"].text == "N/A", "A removed controller shows N/A")
	if "--capture" in OS.get_cmdline_user_args():
		await capture("settings-info")
		view.scroll.scroll_vertical = 10000
		await capture("settings-info-hardware")
	print("Settings failures: ", failures)
	quit(1 if failures else 0)

func capture(filename: String) -> void:
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://dist/" + filename + ".png")
