extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var app: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await create_timer(1).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://dist/login-preview.png")
	var password: LineEdit = app.page.get_child(3)
	password.grab_focus()
	await create_timer(0.3).timeout
	app.keyboard._type("x")
	assert(password.text == "x", "Keyboard edits must reach the selected field")
	app.keyboard._backspace()
	assert(password.text.is_empty(), "Backspace must remove the typed character")
	var address: LineEdit = app.page.get_child(1)
	address.text = ""
	app.keyboard.edit(address)
	await process_frame
	app.keyboard.uppercase = true
	var shortcuts: HBoxContainer = app.keyboard.editor.get_parent().get_child(2)
	shortcuts.get_child(0).pressed.emit()
	assert(address.text == "http://", "The HTTP shortcut stays lowercase with Shift active")
	app.keyboard.editor.select_all()
	app.keyboard._backspace()
	shortcuts.get_child(1).pressed.emit()
	assert(address.text == "https://", "The HTTPS shortcut inserts the complete prefix")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://dist/keyboard-preview.png")
	quit()
