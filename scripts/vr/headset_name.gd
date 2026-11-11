extends RefCounted

const DISPLAY_NAMES := {
	"SteamVR/OpenXR : oculus": "Oculus",
	"SteamVR/OpenXR : cv": "Steam Frame",
}

static func current() -> String:
	var xr := XRServer.find_interface("OpenXR")
	if xr == null or not xr.is_initialized():
		return ""
	var name := str(xr.get_system_info().get("OpenXRSystemName", "")).strip_edges()
	return DISPLAY_NAMES.get(name, name)
