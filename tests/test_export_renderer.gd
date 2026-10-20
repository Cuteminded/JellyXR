extends SceneTree

func _initialize() -> void:
	if not OS.has_feature("windows") and not OS.has_feature("linux"):
		push_error("Run this check on Windows or Linux.")
		quit(1)
		return
	var actual: String = ProjectSettings.get_setting_with_override("rendering/renderer/rendering_method")
	if actual != "mobile":
		push_error("The desktop export must default to Mobile: %s" % actual)
		quit(1)
		return
	if ProjectSettings.get_setting_with_override("rendering/rendering_device/driver") != "vulkan":
		push_error("The desktop export must select the Vulkan driver.")
		quit(1)
		return
	if not ProjectSettings.get_setting_with_override("rendering/rendering_device/fallback_to_opengl3"):
		push_error("The desktop export must allow OpenGL fallback.")
		quit(1)
		return
	if OS.has_feature("windows") and ProjectSettings.get_setting_with_override("rendering/rendering_device/fallback_to_d3d12"):
		push_error("Windows must fall back to OpenGL instead of Direct3D 12.")
		quit(1)
		return
	print("Desktop Vulkan defaults and OpenGL fallback settings: PASS")
	quit()
