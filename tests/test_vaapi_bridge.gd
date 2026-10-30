extends SceneTree

func _initialize() -> void:
    print("Bridge script initialized")
    call_deferred("run_check")

func run_check() -> void:
    print("Bridge script starts native check")
    var node: Node = ClassDB.instantiate("VaapiBridgeNative")
    root.add_child(node)
    RenderingServer.call_on_render_thread(Callable(node, "exercise"))
    var deadline := Time.get_ticks_msec() + 30000
    while not node.has_meta("result") and Time.get_ticks_msec() < deadline:
        await process_frame
    var result: Dictionary = node.get_meta("result", {})
    print("VAAPI render-graph bridge: ", JSON.stringify(result))
    quit(0 if result.get("passed", false) else 1)
