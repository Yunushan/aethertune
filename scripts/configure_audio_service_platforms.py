#!/usr/bin/env python3
"""Apply and verify media-session and secure-storage wrapper settings."""

from __future__ import annotations

import plistlib
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Optional

ANDROID_NAMESPACE = "http://schemas.android.com/apk/res/android"
TOOLS_NAMESPACE = "http://schemas.android.com/tools"
ANDROID = f"{{{ANDROID_NAMESPACE}}}"
TOOLS = f"{{{TOOLS_NAMESPACE}}}"

ANDROID_PERMISSIONS = (
    "android.permission.WAKE_LOCK",
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK",
)
ACTIVITY_NAME = "com.ryanheise.audioservice.AudioServiceActivity"
SERVICE_NAME = "com.ryanheise.audioservice.AudioService"
RECEIVER_NAME = "com.ryanheise.audioservice.MediaButtonReceiver"
IOS_DEPLOYMENT_TARGET = "14.0"
ANDROID_MIN_SDK = 23
KEYCHAIN_ACCESS_GROUPS = "keychain-access-groups"


def _find_named(
    parent: ET.Element, tag: str, name: str
) -> Optional[ET.Element]:
    for element in parent.findall(tag):
        if element.get(f"{ANDROID}name") == name:
            return element
    return None


def _ensure_action(parent: ET.Element, action_name: str) -> None:
    intent_filter = parent.find("intent-filter")
    if intent_filter is None:
        intent_filter = ET.SubElement(parent, "intent-filter")
    for action in intent_filter.findall("action"):
        if action.get(f"{ANDROID}name") == action_name:
            return
    ET.SubElement(intent_filter, "action", {f"{ANDROID}name": action_name})


def configure_android(manifest_path: Path, gradle_path: Path) -> None:
    ET.register_namespace("android", ANDROID_NAMESPACE)
    ET.register_namespace("tools", TOOLS_NAMESPACE)
    tree = ET.parse(manifest_path)
    root = tree.getroot()

    existing_permissions = {
        item.get(f"{ANDROID}name") for item in root.findall("uses-permission")
    }
    application = root.find("application")
    if application is None:
        raise RuntimeError(f"No <application> in {manifest_path}")
    application.set(f"{ANDROID}allowBackup", "false")
    insert_at = list(root).index(application)
    for permission in ANDROID_PERMISSIONS:
        if permission not in existing_permissions:
            root.insert(
                insert_at,
                ET.Element("uses-permission", {f"{ANDROID}name": permission}),
            )
            insert_at += 1

    activity = application.find("activity")
    if activity is None:
        raise RuntimeError(f"No <activity> in {manifest_path}")
    activity.set(f"{ANDROID}name", ACTIVITY_NAME)

    service = _find_named(application, "service", SERVICE_NAME)
    if service is None:
        service = ET.SubElement(application, "service")
    service.attrib.update(
        {
            f"{ANDROID}name": SERVICE_NAME,
            f"{ANDROID}foregroundServiceType": "mediaPlayback",
            f"{ANDROID}exported": "true",
            f"{TOOLS}ignore": "Instantiatable",
        }
    )
    _ensure_action(service, "android.media.browse.MediaBrowserService")

    receiver = _find_named(application, "receiver", RECEIVER_NAME)
    if receiver is None:
        receiver = ET.SubElement(application, "receiver")
    receiver.attrib.update(
        {
            f"{ANDROID}name": RECEIVER_NAME,
            f"{ANDROID}exported": "true",
            f"{TOOLS}ignore": "Instantiatable",
        }
    )
    _ensure_action(receiver, "android.intent.action.MEDIA_BUTTON")

    ET.indent(tree, space="    ")
    tree.write(manifest_path, encoding="utf-8", xml_declaration=True)

    gradle = gradle_path.read_text(encoding="utf-8")
    gradle, replacements = re.subn(
        r"minSdk\s*=\s*flutter\.minSdkVersion",
        f"minSdk = {ANDROID_MIN_SDK}",
        gradle,
    )
    if replacements == 0:
        gradle, replacements = re.subn(
            r"minSdkVersion\s+flutter\.minSdkVersion",
            f"minSdkVersion {ANDROID_MIN_SDK}",
            gradle,
        )
    if replacements == 0 and not re.search(
        rf"(?:minSdk\s*=|minSdkVersion)\s*{ANDROID_MIN_SDK}\b", gradle
    ):
        raise RuntimeError(f"No Android minimum SDK declaration in {gradle_path}")
    gradle_path.write_text(gradle, encoding="utf-8")


def configure_ios(info_plist_path: Path) -> None:
    with info_plist_path.open("rb") as stream:
        info = plistlib.load(stream)
    modes = list(info.get("UIBackgroundModes", []))
    if "audio" not in modes:
        modes.append("audio")
    info["UIBackgroundModes"] = modes
    with info_plist_path.open("wb") as stream:
        plistlib.dump(info, stream, sort_keys=False)


def configure_ios_deployment_target(
    project_path: Path,
    framework_info_path: Path,
) -> None:
    project = project_path.read_text(encoding="utf-8")
    project, replacements = re.subn(
        r"IPHONEOS_DEPLOYMENT_TARGET = [^;]+;",
        f"IPHONEOS_DEPLOYMENT_TARGET = {IOS_DEPLOYMENT_TARGET};",
        project,
    )
    if replacements == 0:
        raise RuntimeError(f"No iOS deployment target in {project_path}")
    project_path.write_text(project, encoding="utf-8")

    with framework_info_path.open("rb") as stream:
        framework_info = plistlib.load(stream)
    framework_info["MinimumOSVersion"] = IOS_DEPLOYMENT_TARGET
    with framework_info_path.open("wb") as stream:
        plistlib.dump(framework_info, stream, sort_keys=False)


def configure_keychain_entitlements(entitlements_path: Path) -> None:
    if entitlements_path.is_file():
        with entitlements_path.open("rb") as stream:
            entitlements = plistlib.load(stream)
    else:
        entitlements = {}
        entitlements_path.parent.mkdir(parents=True, exist_ok=True)
    entitlements[KEYCHAIN_ACCESS_GROUPS] = list(
        entitlements.get(KEYCHAIN_ACCESS_GROUPS, [])
    )
    with entitlements_path.open("wb") as stream:
        plistlib.dump(entitlements, stream, sort_keys=False)


def configure_ios_code_sign_entitlements(project_path: Path) -> None:
    project = project_path.read_text(encoding="utf-8")
    pattern = re.compile(
        r"(buildSettings = \{)(.*?)(\n\s*\};\n\s*name = (Debug|Profile|Release);)",
        re.DOTALL,
    )
    configured = 0

    def update(match: re.Match[str]) -> str:
        nonlocal configured
        body = match.group(2)
        configuration = match.group(4)
        if (
            "PRODUCT_BUNDLE_IDENTIFIER =" not in body
            or ".RunnerTests" in body
        ):
            return match.group(0)
        entitlement_name = (
            "Release.entitlements"
            if configuration == "Release"
            else "DebugProfile.entitlements"
        )
        declaration = f"CODE_SIGN_ENTITLEMENTS = Runner/{entitlement_name};"
        if "CODE_SIGN_ENTITLEMENTS =" in body:
            body = re.sub(
                r"CODE_SIGN_ENTITLEMENTS = [^;]+;",
                declaration,
                body,
            )
        else:
            body = f"{body}\n\t\t\t\t{declaration}"
        configured += 1
        return f"{match.group(1)}{body}{match.group(3)}"

    project = pattern.sub(update, project)
    if configured == 0:
        raise RuntimeError(f"No iOS Runner build settings in {project_path}")
    project_path.write_text(project, encoding="utf-8")


def verify_android(manifest_path: Path, gradle_path: Path) -> None:
    root = ET.parse(manifest_path).getroot()
    permissions = {
        item.get(f"{ANDROID}name") for item in root.findall("uses-permission")
    }
    missing = set(ANDROID_PERMISSIONS) - permissions
    if missing:
        raise RuntimeError(f"Missing Android audio permissions: {sorted(missing)}")
    application = root.find("application")
    if application is None:
        raise RuntimeError("Missing Android application element")
    if application.get(f"{ANDROID}allowBackup") != "false":
        raise RuntimeError("Android backup must be disabled for secure storage")
    activity = application.find("activity")
    if activity is None or activity.get(f"{ANDROID}name") != ACTIVITY_NAME:
        raise RuntimeError("Android activity is not connected to audio_service")
    if _find_named(application, "service", SERVICE_NAME) is None:
        raise RuntimeError("Android audio_service service is missing")
    if _find_named(application, "receiver", RECEIVER_NAME) is None:
        raise RuntimeError("Android media-button receiver is missing")
    gradle = gradle_path.read_text(encoding="utf-8")
    if not re.search(
        rf"(?:minSdk\s*=|minSdkVersion)\s*{ANDROID_MIN_SDK}\b", gradle
    ):
        raise RuntimeError("Android minimum SDK is not 23")


def verify_ios(info_plist_path: Path) -> None:
    with info_plist_path.open("rb") as stream:
        info = plistlib.load(stream)
    if "audio" not in info.get("UIBackgroundModes", []):
        raise RuntimeError("iOS audio background mode is missing")


def verify_ios_deployment_target(
    project_path: Path,
    framework_info_path: Path,
) -> None:
    project = project_path.read_text(encoding="utf-8")
    targets = set(re.findall(r"IPHONEOS_DEPLOYMENT_TARGET = ([^;]+);", project))
    if not targets or targets != {IOS_DEPLOYMENT_TARGET}:
        raise RuntimeError(f"Unexpected iOS deployment targets: {sorted(targets)}")
    with framework_info_path.open("rb") as stream:
        framework_info = plistlib.load(stream)
    if framework_info.get("MinimumOSVersion") != IOS_DEPLOYMENT_TARGET:
        raise RuntimeError("Flutter framework iOS minimum version is not 14.0")


def verify_keychain_entitlements(entitlements_path: Path) -> None:
    with entitlements_path.open("rb") as stream:
        entitlements = plistlib.load(stream)
    if KEYCHAIN_ACCESS_GROUPS not in entitlements:
        raise RuntimeError(
            f"Keychain access groups missing from {entitlements_path}"
        )


def verify_ios_code_sign_entitlements(project_path: Path) -> None:
    project = project_path.read_text(encoding="utf-8")
    declarations = set(
        re.findall(r"CODE_SIGN_ENTITLEMENTS = Runner/([^;]+);", project)
    )
    expected = {"DebugProfile.entitlements", "Release.entitlements"}
    if declarations != expected:
        raise RuntimeError(
            f"Unexpected iOS code-sign entitlements: {sorted(declarations)}"
        )


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: configure_audio_service_platforms.py <flutter-app-dir>")
        return 2
    app_dir = Path(sys.argv[1]).resolve()
    android_manifest = app_dir / "android/app/src/main/AndroidManifest.xml"
    android_gradle = app_dir / "android/app/build.gradle.kts"
    ios_info = app_dir / "ios/Runner/Info.plist"
    ios_project = app_dir / "ios/Runner.xcodeproj/project.pbxproj"
    ios_framework_info = app_dir / "ios/Flutter/AppFrameworkInfo.plist"
    ios_debug_entitlements = app_dir / "ios/Runner/DebugProfile.entitlements"
    ios_release_entitlements = app_dir / "ios/Runner/Release.entitlements"
    macos_debug_entitlements = app_dir / "macos/Runner/DebugProfile.entitlements"
    macos_release_entitlements = app_dir / "macos/Runner/Release.entitlements"
    for path in (
        android_manifest,
        android_gradle,
        ios_info,
        ios_project,
        ios_framework_info,
        macos_debug_entitlements,
        macos_release_entitlements,
    ):
        if not path.is_file():
            raise FileNotFoundError(path)

    configure_android(android_manifest, android_gradle)
    configure_ios(ios_info)
    configure_ios_deployment_target(ios_project, ios_framework_info)
    configure_keychain_entitlements(ios_debug_entitlements)
    configure_keychain_entitlements(ios_release_entitlements)
    configure_keychain_entitlements(macos_debug_entitlements)
    configure_keychain_entitlements(macos_release_entitlements)
    configure_ios_code_sign_entitlements(ios_project)
    verify_android(android_manifest, android_gradle)
    verify_ios(ios_info)
    verify_ios_deployment_target(ios_project, ios_framework_info)
    verify_keychain_entitlements(ios_debug_entitlements)
    verify_keychain_entitlements(ios_release_entitlements)
    verify_keychain_entitlements(macos_debug_entitlements)
    verify_keychain_entitlements(macos_release_entitlements)
    verify_ios_code_sign_entitlements(ios_project)
    print("Configured media controls and cross-platform secure storage.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
