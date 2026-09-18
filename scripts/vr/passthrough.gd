class_name PassthroughEnvironment
extends RefCounted

var xr: Object
var viewport: Viewport
var background: Environment
var opaque_color: Color

func setup(target: Viewport, environment: Environment, interface: Object) -> void:
	viewport = target
	background = environment
	xr = interface
	opaque_color = background.background_color

func is_supported() -> bool:
	return xr != null and xr.is_initialized() and xr.get_supported_environment_blend_modes().has(XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND)

func apply(enabled: bool) -> bool:
	var active := enabled and is_supported()
	viewport.transparent_bg = active
	background.background_color = Color(0, 0, 0, 0) if active else opaque_color
	if xr != null and xr.is_initialized():
		xr.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND if active else XRInterface.XR_ENV_BLEND_MODE_OPAQUE
	return active
