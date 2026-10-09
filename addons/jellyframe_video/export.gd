@tool
extends EditorExportPlugin

func _get_name() -> String:
	return "JellyframeVideo"

func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformAndroid

func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
	return PackedStringArray(["res://addons/jellyframe_video/bin/jellyframe-video-release.aar"])

func _get_android_manifest_activity_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
	return '<intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="com.oculus.intent.category.VR"/></intent-filter>'
