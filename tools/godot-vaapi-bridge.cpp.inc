void RenderingDevice::jellyxr_vulkan_drain() {
    ERR_RENDER_THREAD_GUARD();
    _flush_and_stall_for_all_frames(true);
    for (uint32_t i = 0; i < frames.size(); ++i) {
        while (frames[i].jellyxr_video_jobs.front()) {
            JellyXRVideoJob *job = frames[i].jellyxr_video_jobs.front()->get();
            reinterpret_cast<void (*)(void *)>(job->release)((void *)job->userdata);
            memdelete(job);
            frames[i].jellyxr_video_jobs.pop_front();
        }
    }
}

bool RenderingDevice::jellyxr_vaapi_available() const {
#if defined(LINUXBSD_ENABLED) && defined(VULKAN_ENABLED)
    return driver && driver->get_api_name() == "Vulkan" &&
        static_cast<RenderingDeviceDriverVulkan *>(driver)->jellyxr_vaapi_supported();
#else
    return false;
#endif
}

void RenderingDevice::_jellyxr_record(RDD *p_driver, RDD::CommandBufferID p_command, void *p_userdata) {
#if defined(LINUXBSD_ENABLED) && defined(VULKAN_ENABLED)
    JellyXRVideoJob *job = static_cast<JellyXRVideoJob *>(p_userdata);
    uint64_t command = static_cast<RenderingDeviceDriverVulkan *>(p_driver)->jellyxr_command_buffer(p_command);
    reinterpret_cast<void (*)(uint64_t, void *)>(job->record)(command, (void *)job->userdata);
#endif
}

Error RenderingDevice::jellyxr_vulkan_queue_copy(uint64_t p_record, uint64_t p_release,
        uint64_t p_userdata, const Array &p_targets) {
    ERR_RENDER_THREAD_GUARD_V(ERR_UNAVAILABLE);
    ERR_FAIL_COND_V(driver->get_api_name() != "Vulkan" || !p_record || !p_release || !p_userdata, ERR_UNAVAILABLE);
    ERR_FAIL_COND_V(p_targets.size() != 2, ERR_INVALID_PARAMETER);
    CallbackResource resources[2];
    for (int i = 0; i < 2; ++i) {
        RID rid = p_targets[i];
        Texture *texture = texture_owner.get_or_null(rid);
        ERR_FAIL_NULL_V(texture, ERR_INVALID_PARAMETER);
        ERR_FAIL_COND_V(!(texture->usage_flags & TEXTURE_USAGE_CAN_COPY_TO_BIT), ERR_INVALID_PARAMETER);
        resources[i].rid = rid;
        resources[i].usage = CALLBACK_RESOURCE_USAGE_COPY_TO;
    }
    JellyXRVideoJob *job = memnew(JellyXRVideoJob);
    job->record = p_record;
    job->release = p_release;
    job->userdata = p_userdata;
    Error result = driver_callback_add(_jellyxr_record, job, VectorView<CallbackResource>(resources, 2));
    if (result != OK) {
        memdelete(job);
        return result;
    }
    frames[frame].jellyxr_video_jobs.push_back(job);
    return OK;
}
