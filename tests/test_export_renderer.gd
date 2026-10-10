extends SceneTree

func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 1 or arguments[0] not in ["opengl", "vulkan"]:
		push_error("Specify the expected exported renderer: opengl or vulkan.")
		quit(1)
		return
	var renderer := arguments[0]
	var expected := "mobile" if renderer == "vulkan" else "gl_compatibility"
	var actual: String = ProjectSettings.get_setting_with_override("rendering/renderer/rendering_method")
	if not OS.has_feature("linux_" + renderer) or actual != expected:
		push_error("The exported renderer does not match %s: %s" % [renderer, actual])
		quit(1)
		return
	if renderer == "vulkan" and ProjectSettings.get_setting_with_override("rendering/rendering_device/driver") != "vulkan":
		push_error("The Vulkan export must select the Vulkan driver.")
		quit(1)
		return
	print("Exported %s renderer settings: PASS" % renderer)
	quit()
