#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/rendering_device.hpp>
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/classes/rd_texture_format.hpp>
#include <godot_cpp/classes/rd_texture_view.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <vulkan/vulkan.h>
#include <array>
#include <memory>

using namespace godot;

class VaapiBridgeNative : public Node {
    GDCLASS(VaapiBridgeNative, Node)
    struct Job {
        std::array<VkImage, 2> images;
        std::shared_ptr<int> released;
    };
    static void record(uint64_t value, void *userdata) {
        auto *job = static_cast<Job *>(userdata);
        VkClearColorValue color{};
        color.float32[0] = 1;
        VkImageSubresourceRange range{VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
        for (auto image : job->images)
            vkCmdClearColorImage(reinterpret_cast<VkCommandBuffer>(value), image,
                VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, &color, 1, &range);
    }
    static void release(void *userdata) {
        auto *job = static_cast<Job *>(userdata);
        ++*job->released;
        delete job;
    }
protected:
    static void _bind_methods() { ClassDB::bind_method(D_METHOD("exercise"), &VaapiBridgeNative::exercise); }
public:
    void exercise() {
        UtilityFunctions::print("Bridge check: entered render thread");
        auto *rd = RenderingServer::get_singleton()->get_rendering_device();
        Dictionary result;
        result["passed"] = false;
        if (!rd || !rd->has_method("jellyxr_vulkan_queue_copy")) {
            result["error"] = "Engine adapter missing";
            call_deferred("set_meta", "result", result);
            return;
        }
        bool passed = true;
        auto released = std::make_shared<int>(0);
        for (bool ten_bit : {false, true}) {
            Array targets;
            Ref<RDTextureView> view;
            view.instantiate();
            for (int i = 0; i < 2; ++i) {
                Ref<RDTextureFormat> format;
                format.instantiate();
                format->set_texture_type(RenderingDevice::TEXTURE_TYPE_2D);
                format->set_width(i ? 10 : 19);
                format->set_height(i ? 7 : 13);
                format->set_format(ten_bit ? (i ? RenderingDevice::DATA_FORMAT_R16G16_UNORM : RenderingDevice::DATA_FORMAT_R16_UNORM) :
                    (i ? RenderingDevice::DATA_FORMAT_R8G8_UNORM : RenderingDevice::DATA_FORMAT_R8_UNORM));
                format->set_usage_bits(RenderingDevice::TEXTURE_USAGE_SAMPLING_BIT |
                    RenderingDevice::TEXTURE_USAGE_CAN_COPY_TO_BIT | RenderingDevice::TEXTURE_USAGE_CAN_COPY_FROM_BIT);
                targets.push_back(rd->texture_create(format, view));
            }
            for (int iteration = 0; iteration < 6; ++iteration) {
                UtilityFunctions::print("Bridge check: queue ", iteration, " ten_bit=", ten_bit);
                auto job = std::make_unique<Job>();
                job->released = released;
                for (int i = 0; i < 2; ++i)
                    job->images[i] = (VkImage)rd->get_driver_resource(RenderingDevice::DRIVER_RESOURCE_TEXTURE, targets[i], 0);
                int64_t status = rd->call("jellyxr_vulkan_queue_copy", uint64_t(&record), uint64_t(&release), uint64_t(job.get()), targets);
                if (status != OK) { passed = false; break; }
                job.release();
                UtilityFunctions::print("Bridge check: queued");
                for (int i = 0; i < 2; ++i) {
                    auto bytes = rd->texture_get_data(targets[i], 0);
                    UtilityFunctions::print("Bridge check: read plane ", i);
                    int sample_bytes = ten_bit ? 2 : 1;
                    int pixel_bytes = sample_bytes * (i ? 2 : 1);
                    int expected_size = (i ? 10 * 7 : 19 * 13) * pixel_bytes;
                    passed = passed && bytes.size() == expected_size;
                    for (int64_t j = 0; j < bytes.size(); ++j)
                        passed = passed && bytes[j] == (j % pixel_bytes < sample_bytes ? 255 : 0);
                }
            }
            for (int i = 0; i < 2; ++i) rd->free_rid(targets[i]);
        }
        rd->call("jellyxr_vulkan_drain");
        UtilityFunctions::print("Bridge check: drained");
        result["released_jobs"] = *released;
        result["passed"] = passed && *released == 12;
        call_deferred("set_meta", "result", result);
    }
};

static void initialize(ModuleInitializationLevel level) {
    if (level == MODULE_INITIALIZATION_LEVEL_SCENE) ClassDB::register_class<VaapiBridgeNative>();
}
static void terminate(ModuleInitializationLevel) {}
extern "C" GDExtensionBool GDE_EXPORT vaapi_bridge_test_init(GDExtensionInterfaceGetProcAddress address,
        GDExtensionClassLibraryPtr library, GDExtensionInitialization *initialization) {
    GDExtensionBinding::InitObject init(address, library, initialization);
    init.register_initializer(initialize);
    init.register_terminator(terminate);
    init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init.init();
}
