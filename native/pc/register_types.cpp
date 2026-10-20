#include "mpv_video.h"
#include <godot_cpp/godot.hpp>

using namespace godot;

static void initialize(ModuleInitializationLevel level) {
    if (level == MODULE_INITIALIZATION_LEVEL_SCENE) {
        ClassDB::register_internal_class<RenderGl>();
        ClassDB::register_internal_class<RenderVulkan>();
        ClassDB::register_class<JellyframeMpv>();
    }
}

static void terminate(ModuleInitializationLevel) {}

extern "C" GDExtensionBool GDE_EXPORT jellyframe_mpv_init(
    GDExtensionInterfaceGetProcAddress get_proc_address,
    GDExtensionClassLibraryPtr library,
    GDExtensionInitialization *initialization) {
    GDExtensionBinding::InitObject init(get_proc_address, library, initialization);
    init.register_initializer(initialize);
    init.register_terminator(terminate);
    init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init.init();
}
