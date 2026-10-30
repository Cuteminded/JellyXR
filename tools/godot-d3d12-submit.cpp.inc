        LocalVector<uint64_t> video_wait_values, video_signal_values;
        for (uint32_t i = 0; i < wait_semaphores.size(); ++i) video_wait_values.push_back(0);
        bool has_video_fences = false;
        for (uint32_t i = 0; i < p_cmd_buffers.size(); ++i) {
            const auto *buffer = (CommandBufferInfo *)p_cmd_buffers[i].id;
            for (uint32_t j = 0; j < buffer->jellyxr_video_waits.size(); ++j) {
                wait_semaphores.push_back(buffer->jellyxr_video_waits[j]);
                wait_semaphores_stages.push_back(VK_PIPELINE_STAGE_TRANSFER_BIT);
                video_wait_values.push_back(buffer->jellyxr_video_values[j]);
                has_video_fences = true;
            }
        }
        for (uint32_t i = 0; i < signal_semaphores.size(); ++i) video_signal_values.push_back(0);
        VkD3D12FenceSubmitInfoKHR video_fences = {};
        video_fences.sType = VK_STRUCTURE_TYPE_D3D12_FENCE_SUBMIT_INFO_KHR;
        video_fences.waitSemaphoreValuesCount = video_wait_values.size();
        video_fences.pWaitSemaphoreValues = video_wait_values.ptr();
        video_fences.signalSemaphoreValuesCount = video_signal_values.size();
        video_fences.pSignalSemaphoreValues = video_signal_values.ptr();
