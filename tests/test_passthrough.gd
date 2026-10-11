extends SceneTree

class FakeXR extends RefCounted:
	var supported := true
	var initialized := true
	var environment_blend_mode := XRInterface.XR_ENV_BLEND_MODE_OPAQUE
	func is_initialized() -> bool: return initialized
	func get_supported_environment_blend_modes() -> Array:
		return [XRInterface.XR_ENV_BLEND_MODE_OPAQUE, XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND] if supported else [XRInterface.XR_ENV_BLEND_MODE_OPAQUE]

func _initialize() -> void:
	var xr := FakeXR.new()
	var background := Environment.new()
	background.background_mode = Environment.BG_COLOR
	background.background_color = Color("05080cff")
	var original := background.background_color
	var passthrough := PassthroughEnvironment.new()
	passthrough.setup(root, background, xr)
	assert(passthrough.apply(true))
	assert(root.transparent_bg and background.background_color.a == 0)
	assert(xr.environment_blend_mode == XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND)
	assert(not passthrough.apply(false))
	assert(not root.transparent_bg and background.background_color == original)
	assert(xr.environment_blend_mode == XRInterface.XR_ENV_BLEND_MODE_OPAQUE)
	xr.supported = false
	assert(not passthrough.apply(true))
	assert(not root.transparent_bg and background.background_color == original)
	xr.supported = true
	xr.initialized = false
	assert(not passthrough.is_supported())
	passthrough.setup(root, background, null)
	assert(not passthrough.apply(true))
	print("Passthrough blending, opaque restoration and unsupported fallback passed.")
	quit()
