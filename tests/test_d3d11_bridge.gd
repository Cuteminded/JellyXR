extends SceneTree

func _initialize() -> void:
	var passed := true
	for method in ["jellyxr_d3d11_available", "jellyxr_d3d12_available", "jellyxr_vulkan_queue_copy", "jellyxr_vulkan_drain"]:
		if not ClassDB.class_has_method("RenderingDevice", method):
			push_error("Windows export is missing the GPU adapter method: " + method)
			passed = false
	for method in ClassDB.class_get_method_list("RenderingDevice"):
		if method.name == "jellyxr_vulkan_queue_copy":
			passed = passed and method.args.size() == 5 and method.default_args.size() == 1
	print("Windows D3D11/D3D12 render-graph adapters: ", "PASS" if passed else "FAIL")
	quit(0 if passed else 1)
