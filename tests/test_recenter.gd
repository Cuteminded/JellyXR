extends SceneTree

var calls := 0

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var startup := StartupRecenter.new()
	root.add_child(startup)
	startup.ready_to_center.connect(func(): calls += 1)
	startup.update_tracking(false, 10.0)
	assert(calls == 0, "Do not center before headset tracking starts")
	startup.update_tracking(true, 0.2)
	startup.update_tracking(false, 0.1)
	startup.update_tracking(true, 0.2)
	assert(calls == 0, "Tracking loss resets the settling period")
	startup.update_tracking(true, 0.2)
	assert(calls == 1, "Stable tracking centers once")
	startup.update_tracking(true, 10.0)
	assert(calls == 1, "Normal head movement does not keep recentering")
	var app: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	var menu_transform: Transform3D = app.panel.global_transform
	var movie_transform: Transform3D = app.screen.global_transform
	app.camera.position += Vector3(0.4, 0.2, 0.0)
	app.camera.rotate_y(0.5)
	root.use_xr = true
	app.panel.show()
	app._toggle_menu()
	assert(not app.panel.visible, "The controller hides the menu")
	app._toggle_menu()
	assert(app.panel.visible, "The controller shows the menu again")
	assert(app.panel.global_transform == menu_transform, "Menu toggling preserves its world position and orientation")
	assert(app.screen.global_transform == movie_transform, "Menu toggling does not reposition the movie")
	app._recenter()
	assert(app.panel.global_transform != menu_transform, "Explicit recenter still follows the current viewing position")
	root.use_xr = false
	print("Startup recenter checks: PASS")
	quit()
