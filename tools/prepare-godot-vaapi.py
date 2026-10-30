"""Apply the jellyXR VAAPI render-graph bridge to Godot 4.7.2 source."""

import argparse
from pathlib import Path


def replace_once(root, path, before, after):
    target = root / path
    content = target.read_text(encoding="utf-8")
    if content.count(before) != 1:
        raise RuntimeError(f"Unexpected Godot source in {path}: {before[:70]!r}")
    return target, content.replace(before, after, 1)


def prepare(root):
    changes = []
    changes.append(replace_once(root, "servers/rendering/rendering_device_graph.cpp",
        "\tcommand->type = RecordedCommand::TYPE_DRIVER_CALLBACK;",
        "\tcommand->type = RecordedCommand::TYPE_DRIVER_CALLBACK;\n"
        "\tcommand->self_stages = RDD::PIPELINE_STAGE_ALL_COMMANDS_BIT;"))
    changes.append(replace_once(root, "drivers/vulkan/rendering_device_driver_vulkan.cpp",
        "\t_register_requested_device_extension(VK_KHR_EXTERNAL_MEMORY_FD_EXTENSION_NAME, false);",
        "\t_register_requested_device_extension(VK_KHR_EXTERNAL_MEMORY_FD_EXTENSION_NAME, false);\n"
        "#ifdef LINUXBSD_ENABLED\n"
        "\t_register_requested_device_extension(VK_EXT_EXTERNAL_MEMORY_DMA_BUF_EXTENSION_NAME, false);\n"
        "\t_register_requested_device_extension(VK_EXT_IMAGE_DRM_FORMAT_MODIFIER_EXTENSION_NAME, false);\n"
        "\t_register_requested_device_extension(VK_EXT_QUEUE_FAMILY_FOREIGN_EXTENSION_NAME, false);\n"
        "\t_register_requested_device_extension(VK_EXT_PHYSICAL_DEVICE_DRM_EXTENSION_NAME, false);\n"
        "#endif"))
    changes.append(replace_once(root, "drivers/vulkan/rendering_device_driver_vulkan.h",
        "\tRenderingDeviceDriverVulkan(RenderingContextDriverVulkan *p_context_driver);",
        "\tuint64_t jellyxr_command_buffer(CommandBufferID p_buffer) const {\n"
        "\t\treturn (uint64_t)((CommandBufferInfo *)p_buffer.id)->vk_command_buffer;\n\t}\n"
        "\tbool jellyxr_vaapi_supported() const {\n"
        "\t\treturn enabled_device_extension_names.has(VK_KHR_EXTERNAL_MEMORY_FD_EXTENSION_NAME) &&\n"
        "\t\t\tenabled_device_extension_names.has(VK_EXT_PHYSICAL_DEVICE_DRM_EXTENSION_NAME) &&\n"
        "\t\t\tenabled_device_extension_names.has(VK_EXT_EXTERNAL_MEMORY_DMA_BUF_EXTENSION_NAME) &&\n"
        "\t\t\tenabled_device_extension_names.has(VK_EXT_IMAGE_DRM_FORMAT_MODIFIER_EXTENSION_NAME) &&\n"
        "\t\t\tenabled_device_extension_names.has(VK_EXT_QUEUE_FAMILY_FOREIGN_EXTENSION_NAME);\n\t}\n"
        "\tRenderingDeviceDriverVulkan(RenderingContextDriverVulkan *p_context_driver);"))
    changes.append(replace_once(root, "servers/rendering/rendering_device.h", "\tstruct Frame {",
        "\tstruct JellyXRVideoJob { uint64_t record; uint64_t release; uint64_t userdata; };\n"
        "\tstatic void _jellyxr_record(RDD *p_driver, RDD::CommandBufferID p_command, void *p_userdata);\n"
        "\tstruct Frame {\n\t\tList<JellyXRVideoJob *> jellyxr_video_jobs;"))
    # The header receives two independent additions in one staged update.
    target, content = changes[-1]
    marker = "\tError driver_callback_add(RDD::DriverCallback p_callback, void *p_userdata, VectorView<CallbackResource> p_resources);"
    if content.count(marker) != 1:
        raise RuntimeError("Missing Godot driver callback declaration")
    content = content.replace(marker, marker + "\n\tbool jellyxr_vaapi_available() const;\n"
        "\tvoid jellyxr_vulkan_drain();\n\tError jellyxr_vulkan_queue_copy(uint64_t p_record, uint64_t p_release, uint64_t p_userdata, const Array &p_targets);", 1)
    changes[-1] = target, content
    path = "servers/rendering/rendering_device.cpp"
    target = root / path
    content = target.read_text(encoding="utf-8")
    marker = '#include "rendering_device.h"'
    content = content.replace(marker, marker + '\n#if defined(LINUXBSD_ENABLED) && defined(VULKAN_ENABLED)\n'
        '#include "drivers/vulkan/rendering_device_driver_vulkan.h"\n#endif', 1)
    marker = "void RenderingDevice::_free_pending_resources(int p_frame) {"
    if content.count(marker) != 1:
        raise RuntimeError("Missing Godot frame resource cleanup")
    content = content.replace(marker, marker + "\n\twhile (frames[p_frame].jellyxr_video_jobs.front()) {\n"
        "\t\tJellyXRVideoJob *job = frames[p_frame].jellyxr_video_jobs.front()->get();\n"
        "\t\treinterpret_cast<void (*)(void *)>(job->release)((void *)job->userdata);\n"
        "\t\tmemdelete(job);\n\t\tframes[p_frame].jellyxr_video_jobs.pop_front();\n\t}", 1)
    implementation = (Path(__file__).parent / "godot-vaapi-bridge.cpp.inc").read_text(encoding="utf-8")
    marker = "void RenderingDevice::_bind_methods() {"
    if content.count(marker) != 1:
        raise RuntimeError("Missing Godot method binding")
    content = content.replace(marker, implementation + "\n" + marker + "\n"
        '\tClassDB::bind_method(D_METHOD("jellyxr_vaapi_available"), &RenderingDevice::jellyxr_vaapi_available);\n'
        '\tClassDB::bind_method(D_METHOD("jellyxr_vulkan_drain"), &RenderingDevice::jellyxr_vulkan_drain);\n'
        '\tClassDB::bind_method(D_METHOD("jellyxr_vulkan_queue_copy", "record", "release", "userdata", "targets"), &RenderingDevice::jellyxr_vulkan_queue_copy);', 1)
    changes.append((target, content))
    for target, content in changes:
        target.write_text(content, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("godot_source", type=Path)
    prepare(parser.parse_args().godot_source.resolve())
