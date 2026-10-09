class_name StartupRecenter
extends Node

signal ready_to_center
var settled := 0.0
var completed := false

func update_tracking(valid: bool, delta: float) -> void:
	if completed: return
	settled = settled + delta if valid else 0.0
	if settled >= 0.35:
		completed = true
		ready_to_center.emit()

func _process(delta: float) -> void:
	if completed or not get_viewport().use_xr: return
	var xr := XRServer.find_interface("OpenXR") as OpenXRInterface
	if not xr or xr.get_session_state() != OpenXRInterface.SESSION_STATE_FOCUSED:
		update_tracking(false, delta)
		return
	var head := XRServer.get_tracker("head") as XRPositionalTracker
	var pose: XRPose = head.get_pose("default") if head else null
	update_tracking(pose != null and pose.has_tracking_data, delta)
