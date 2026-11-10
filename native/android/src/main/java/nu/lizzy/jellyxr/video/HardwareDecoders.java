package nu.lizzy.jellyxr.video;

import android.media.MediaCodecInfo;
import android.media.MediaCodecInfo.CodecCapabilities;
import android.media.MediaCodecInfo.CodecProfileLevel;
import android.media.MediaCodecList;
import android.media.MediaFormat;
import android.util.Log;
import java.util.Locale;
import java.util.TreeSet;

final class HardwareDecoders {
static final int UNKNOWN = 0;
static final int HARDWARE = 1;
static final int UNSUPPORTED = 2;
private volatile MediaCodecInfo[] codecs;
private volatile String summary = "Checking Android hardware decoders...";

void scan() {
try {
MediaCodecInfo[] devices = new MediaCodecList(MediaCodecList.REGULAR_CODECS).getCodecInfos();
TreeSet<String> types = new TreeSet<>();
        for (MediaCodecInfo device : devices) {
        if (device.isEncoder() || !device.isHardwareAccelerated()) continue;
        for (String type : device.getSupportedTypes()) {
        if (type.startsWith("video/")) types.add(type.substring("video/".length()));
        }
        }
        codecs = devices;
        summary = types.isEmpty() ? "Android reported no hardware video decoders."
        : "Android reported hardware decoders for " + String.join(", ", types) + ".";
        } catch (RuntimeException error) {
        summary = "Android hardware decoder information is unavailable.";
        Log.w("JellyXRVideo", "Cannot query Android video decoders", error);
        }
        }

        String summary() { return summary; }

        int active(String name) {
        MediaCodecInfo[] devices = codecs;
        if (devices == null) return UNKNOWN;
        for (MediaCodecInfo codec : devices) {
        if (name.equals(codec.getName()) || name.equals(codec.getCanonicalName())) {
        return codec.isHardwareAccelerated() ? HARDWARE
        : codec.isSoftwareOnly() ? UNSUPPORTED : UNKNOWN;
        }
        }
        return UNKNOWN;
        }

        int supports(String codec, String profile, int depth, int width, int height, double fps) {
        MediaCodecInfo[] devices = codecs;
        String mime = mimeType(codec);
        if (devices == null || mime == null) return UNKNOWN;
        int requestedProfile = profile(codec, profile.toLowerCase(Locale.ROOT), depth);
        boolean uncertain = false;
        for (MediaCodecInfo device : devices) {
        if (device.isEncoder() || !device.isHardwareAccelerated()) continue;
        for (String type : device.getSupportedTypes()) {
        if (!type.equalsIgnoreCase(mime)) continue;
        try {
        CodecCapabilities caps = device.getCapabilitiesForType(type);
        if (requestedProfile == 0 || width <= 0 || height <=0 || fps <=0) { uncertain=true; continue; } MediaFormat
            format=MediaFormat.createVideoFormat(type, width, height); format.setInteger(MediaFormat.KEY_PROFILE,
            requestedProfile); format.setFloat(MediaFormat.KEY_FRAME_RATE, (float) fps); if
            (caps.isFormatSupported(format) && caps.getVideoCapabilities().areSizeAndRateSupported(width, height, fps))
            { return HARDWARE; } } catch (RuntimeException error) { uncertain=true; } } } return uncertain ? UNKNOWN :
            UNSUPPORTED; } private static String mimeType(String codec) { switch (codec) { case "h264" : return
            MediaFormat.MIMETYPE_VIDEO_AVC; case "hevc" : return MediaFormat.MIMETYPE_VIDEO_HEVC; case "av1" : return
            MediaFormat.MIMETYPE_VIDEO_AV1; case "vp8" : return MediaFormat.MIMETYPE_VIDEO_VP8; case "vp9" : return
            MediaFormat.MIMETYPE_VIDEO_VP9; case "mpeg2video" : return MediaFormat.MIMETYPE_VIDEO_MPEG2; case "mpeg4" :
            return MediaFormat.MIMETYPE_VIDEO_MPEG4; default: return null; } } private static int profile(String codec,
            String profile, int depth) { if (codec.equals("h264") && depth==8) { switch (profile) {
            case "constrained baseline" : return CodecProfileLevel.AVCProfileConstrainedBaseline; case "baseline" :
            return CodecProfileLevel.AVCProfileBaseline; case "main" : return CodecProfileLevel.AVCProfileMain;
            case "high" : return CodecProfileLevel.AVCProfileHigh; default: return 0; } } if (codec.equals("hevc")) { if
            (profile.equals("main") && depth==8) return CodecProfileLevel.HEVCProfileMain; if (profile.equals("main 10")
            && depth==10) return CodecProfileLevel.HEVCProfileMain10; } if (codec.equals("vp9")) { if
            (profile.equals("profile 0") && depth==8) return CodecProfileLevel.VP9Profile0; if (profile.equals("profile
            2") && depth==10) return CodecProfileLevel.VP9Profile2; } if (codec.equals("av1") && profile.equals("main"))
            { if (depth==8) return CodecProfileLevel.AV1ProfileMain8; if (depth==10) return
            CodecProfileLevel.AV1ProfileMain10; } return 0; } }
