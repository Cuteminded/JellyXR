"""Apply Windows D3D11/D3D12 video submission adapters to Godot 4.7.2."""

import argparse
import importlib.util
from pathlib import Path


def prepare(root):
    specification = importlib.util.spec_from_file_location("video_bridge", Path(__file__).with_name("prepare-godot-vaapi.py"))
    bridge = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(bridge)
    bridge.prepare(root)
    changes = []
    header = "drivers/vulkan/rendering_device_driver_vulkan.h"
    changes.append(bridge.replace_once(root, header,
        "\tstruct CommandBufferInfo {",
        "\tstruct CommandBufferInfo {\n#ifdef WINDOWS_ENABLED\n"
        "\t\tLocalVector<VkDeviceMemory> jellyxr_video_memories;\n"
        "\t\tLocalVector<VkSemaphore> jellyxr_video_waits;\n"
        "\t\tLocalVector<uint64_t> jellyxr_video_values;\n#endif"))
    target, content = changes[-1]
    marker = "\tRenderingDeviceDriverVulkan(RenderingContextDriverVulkan *p_context_driver);"
    content = content.replace(marker,
        "#ifdef WINDOWS_ENABLED\n"
        "\tbool jellyxr_d3d11_supported() const {\n"
        "\t\treturn enabled_device_extension_names.has(VK_KHR_EXTERNAL_MEMORY_WIN32_EXTENSION_NAME) &&\n"
        "\t\t\tenabled_device_extension_names.has(VK_KHR_WIN32_KEYED_MUTEX_EXTENSION_NAME);\n\t}\n"
        "\tbool jellyxr_d3d12_supported() const {\n"
        "\t\treturn enabled_device_extension_names.has(VK_KHR_EXTERNAL_MEMORY_WIN32_EXTENSION_NAME) &&\n"
        "\t\t\tenabled_device_extension_names.has(VK_KHR_EXTERNAL_SEMAPHORE_WIN32_EXTENSION_NAME);\n\t}\n"
        "\tvoid jellyxr_d3d12_sync(CommandBufferID p_buffer, uint64_t p_semaphore, uint64_t p_value) {\n"
        "\t\tauto *buffer = (CommandBufferInfo *)p_buffer.id;\n"
        "\t\tbuffer->jellyxr_video_waits.push_back((VkSemaphore)p_semaphore);\n"
        "\t\tbuffer->jellyxr_video_values.push_back(p_value);\n\t}\n"
        "\tvoid jellyxr_d3d11_sync(CommandBufferID p_buffer, uint64_t p_y, uint64_t p_uv) {\n"
        "\t\tauto &memories = ((CommandBufferInfo *)p_buffer.id)->jellyxr_video_memories;\n"
        "\t\tmemories.push_back((VkDeviceMemory)p_y);\n\t\tmemories.push_back((VkDeviceMemory)p_uv);\n\t}\n"
        "#endif\n" + marker, 1)
    changes[-1] = target, content
    path = "drivers/vulkan/rendering_device_driver_vulkan.cpp"
    target = root / path
    content = target.read_text(encoding="utf-8")
    def replace(before, after):
        nonlocal content
        if content.count(before) != 1:
            raise RuntimeError(f"Unexpected Vulkan source: {before[:80]!r}")
        content = content.replace(before, after, 1)
    marker = "\t_register_requested_device_extension(VK_KHR_EXTERNAL_MEMORY_FD_EXTENSION_NAME, false);"
    replace(marker, marker + "\n#ifdef WINDOWS_ENABLED\n"
        "\t_register_requested_device_extension(VK_KHR_EXTERNAL_MEMORY_WIN32_EXTENSION_NAME, false);\n"
        "\t_register_requested_device_extension(VK_KHR_WIN32_KEYED_MUTEX_EXTENSION_NAME, false);\n"
        "\t_register_requested_device_extension(VK_KHR_EXTERNAL_SEMAPHORE_WIN32_EXTENSION_NAME, false);\n#endif")
    marker = "bool RenderingDeviceDriverVulkan::command_buffer_begin(CommandBufferID p_cmd_buffer) {"
    replace(marker, marker + "\n#ifdef WINDOWS_ENABLED\n"
        "\t((CommandBufferInfo *)p_cmd_buffer.id)->jellyxr_video_memories.clear();\n"
        "\t((CommandBufferInfo *)p_cmd_buffer.id)->jellyxr_video_waits.clear();\n"
        "\t((CommandBufferInfo *)p_cmd_buffer.id)->jellyxr_video_values.clear();\n#endif")
    marker = "\t\tVkSubmitInfo submit_info = {};"
    submission = (Path(__file__).parent / "godot-d3d12-submit.cpp.inc").read_text(encoding="utf-8")
    replace(marker, "#ifdef WINDOWS_ENABLED\n"
        "\t\tLocalVector<VkDeviceMemory> video_memories;\n"
        "\t\tLocalVector<uint64_t> acquire_keys, release_keys;\n"
        "\t\tLocalVector<uint32_t> timeouts;\n"
        "\t\tfor (uint32_t i = 0; i < p_cmd_buffers.size(); ++i) {\n"
        "\t\t\tconst auto &memories = ((CommandBufferInfo *)p_cmd_buffers[i].id)->jellyxr_video_memories;\n"
        "\t\t\tfor (uint32_t j = 0; j < memories.size(); ++j) {\n"
        "\t\t\t\tvideo_memories.push_back(memories[j]);\n"
        "\t\t\t\tacquire_keys.push_back(1);\n\t\t\t\trelease_keys.push_back(0);\n"
        "\t\t\t\ttimeouts.push_back(5000);\n\t\t\t}\n\t\t}\n"
        "\t\tVkWin32KeyedMutexAcquireReleaseInfoKHR video_sync = {};\n"
        "\t\tvideo_sync.sType = VK_STRUCTURE_TYPE_WIN32_KEYED_MUTEX_ACQUIRE_RELEASE_INFO_KHR;\n"
        "\t\tvideo_sync.acquireCount = video_sync.releaseCount = video_memories.size();\n"
        "\t\tvideo_sync.pAcquireSyncs = video_sync.pReleaseSyncs = video_memories.ptr();\n"
        "\t\tvideo_sync.pAcquireKeys = acquire_keys.ptr();\n"
        "\t\tvideo_sync.pReleaseKeys = release_keys.ptr();\n"
        "\t\tvideo_sync.pAcquireTimeouts = timeouts.ptr();\n" + submission + "\n#endif\n" + marker)
    marker = "\t\tsubmit_info.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;"
    replace(marker, marker + "\n#ifdef WINDOWS_ENABLED\n"
        "\t\tif (!video_memories.is_empty()) submit_info.pNext = &video_sync;\n"
        "\t\tif (has_video_fences) {\n"
        "\t\t\tvideo_fences.pNext = submit_info.pNext;\n"
        "\t\t\tsubmit_info.pNext = &video_fences;\n\t\t}\n#endif")
    changes.append((target, content))
    for target, content in changes:
        target.write_text(content, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("godot_source", type=Path)
    prepare(parser.parse_args().godot_source.resolve())
