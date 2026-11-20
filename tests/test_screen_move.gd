extends SceneTree

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var app: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	app.world.set_process(false)
	app.settings.environment = "Void"
	app.screen.show()
	var tracker := XRControllerTracker.new()
	tracker.name = &"left_hand"
	tracker.type = XRServer.TRACKER_CONTROLLER
	tracker.set_pose(&"aim", Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	XRServer.add_tracker(tracker)
	var pointer := LaserPointer.new()
	pointer.tracker = &"left_hand"
	pointer.pose = &"aim"
	pointer.panel = app.panel
	pointer.viewport = app.viewport
	app.world.camera.get_parent().add_child(pointer)
	pointer.set_process(false)
	app.world.pointers.append(pointer)
	pointer.button_pressed.connect(app.world._controller_button_pressed.bind(pointer.tracker))
	pointer.button_released.connect(app.world._controller_button_released.bind(pointer.tracker))
	await process_frame
	app.settings.controller_bindings.assign("left_hand/grip_click", "move_screen")
	app.settings.follow_screen = true
	var initial: Transform3D = app.screen.global_transform
	tracker.set_input(&"grip_click", true)
	assert(app.world.moving_controller == pointer, "The assigned hand starts moving the screen")
	assert(app.screen.global_transform.is_equal_approx(initial), "Grabbing does not snap the screen")
	assert(not app.settings.follow_screen, "Grabbing disables head following")
	var motion := Transform3D(Basis(Vector3.UP, 0.3), Vector3(0.5, 0.2, -0.1))
	pointer.transform = motion
	app.world._update_screen_move()
	assert(app.screen.global_transform.is_equal_approx(motion * initial), "The screen follows controller translation and rotation")
	var moved: Transform3D = app.screen.global_transform
	app.world._controller_button_released("grip_click", &"right_hand")
	assert(app.world.moving_controller == pointer, "The other hand cannot release the screen")
	app.world._controller_button_released("ax_button", &"left_hand")
	assert(app.world.moving_controller == pointer, "Other buttons cannot release the screen")
	tracker.set_input(&"grip_click", false)
	pointer.position += Vector3.ONE
	app.world._update_screen_move()
	assert(app.world.moving_controller == null and app.screen.global_transform.is_equal_approx(moved), "Releasing leaves the screen in place")
	for environment in ["Cinema", "Theatre"]:
		app.settings.environment = environment
		tracker.set_input(&"grip_click", true)
		assert(app.world.moving_controller == null, "Cinema screens stay fixed")
		tracker.set_input(&"grip_click", false)
	app.settings.environment = "Passthrough"
	app.world.panoramic = true
	tracker.set_input(&"grip_click", true)
	assert(app.world.moving_controller == null, "Panoramic video cannot be grabbed")
	tracker.set_input(&"grip_click", false)
	app.world.panoramic = false
	tracker.set_input(&"grip_click", true)
	assert(app.world.moving_controller == pointer, "Passthrough allows screen movement")
	tracker.invalidate_pose(&"aim")
	await process_frame
	app.world._update_screen_move()
	assert(app.world.moving_controller == null, "Losing tracking releases the screen")
	tracker.set_input(&"grip_click", false)
	tracker.set_pose(&"aim", Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	await process_frame
	tracker.set_input(&"grip_click", true)
	app._recenter_video()
	assert(app.world.moving_controller == null, "Recentering releases the screen")
	tracker.set_input(&"grip_click", false)
	app.screen.hide()
	tracker.set_input(&"grip_click", true)
	assert(app.world.moving_controller == null, "A hidden screen cannot be grabbed")
	XRServer.remove_tracker(tracker)
	app.queue_free()
	await process_frame
	print("Screen move checks: PASS")
	quit()
