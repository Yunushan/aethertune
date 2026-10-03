#!/usr/bin/env python3
"""Fail-closed Developer ID signing policy and archive-bound capability evidence.

Decoded-profile checks are supplementary CI policy, not Apple authorization.
The reviewed profile hash binds the input; codesign, notarization and ordinary
installed execution remain separate native requirements.
The final receipt is included in the release's GitHub-attested subject inventory.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
import posixpath
import re
import stat
import struct
import subprocess
import sys
import tempfile
import zipfile
import uuid
import unicodedata
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath

CAPABILITIES = {
    "com.apple.security.app-sandbox": True,
    "com.apple.security.network.client": True,
    "com.apple.security.files.user-selected.read-write": True,
}
APP_ID = "com.apple.application-identifier"
TEAM_ID = "com.apple.developer.team-identifier"
GROUPS = "keychain-access-groups"
ARCHES = {"arm64", "x86_64"}
MACHO = {bytes.fromhex(x) for x in ("feedface", "cefaedfe", "feedfacf", "cffaedfe", "cafebabe", "bebafeca", "cafebabf", "bfbafeca")}


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def require(ok: bool, message: str) -> None:
    if not ok:
        raise ValueError(message)


def identity(team: str, bundle: str) -> None:
    require(bool(re.fullmatch(r"[A-Z0-9]{10}", team)), "invalid expected team ID")
    require(bool(re.fullmatch(r"[A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)+", bundle)), "invalid expected bundle ID")


def allowed(claim: str, allowlist: object) -> bool:
    if not isinstance(allowlist, str):
        return False
    return claim == allowlist or (allowlist.endswith(".*") and "*" not in allowlist[:-1]
                                 and claim.startswith(allowlist[:-1]))


def validate_profile(profile: dict, team: str, bundle: str, certificate_sha1: str,
                     release: dict, now: datetime | None = None) -> dict:
    """Check supplementary decoded metadata. Fixtures only test this policy layer."""
    identity(team, bundle)
    require(bool(re.fullmatch(r"[0-9a-f]{40}", certificate_sha1)), "invalid certificate fingerprint")
    require(isinstance(profile, dict), "profile payload is not a dictionary")
    now = now or datetime.now(timezone.utc)
    expiry = profile.get("ExpirationDate")
    require(isinstance(expiry, datetime), "profile expiration is missing")
    require((expiry.replace(tzinfo=timezone.utc) if expiry.tzinfo is None else expiry.astimezone(timezone.utc)) > now, "profile is expired")
    creation = profile.get("CreationDate")
    require(isinstance(creation, datetime) and (creation.replace(tzinfo=timezone.utc) if creation.tzinfo is None else creation.astimezone(timezone.utc)) <= now,
            "profile creation is missing or in the future")
    require(profile.get("TeamIdentifier") == [team], "profile belongs to a different team")
    require(profile.get("ProvisionsAllDevices") is True and not profile.get("ProvisionedDevices"),
            "profile is not unrestricted Developer ID distribution")
    platform = profile.get("Platform")
    require(platform in (["OSX"], ["macOS"]), "profile is not macOS")
    certificates = profile.get("DeveloperCertificates")
    require(isinstance(certificates, list) and certificates and all(isinstance(c, bytes) for c in certificates),
            "profile certificate allowlist is missing")
    require(certificate_sha1.lower() in {hashlib.sha1(c).hexdigest() for c in certificates},
            "signing certificate is not authorized by profile")
    ent = profile.get("Entitlements")
    require(isinstance(ent, dict), "profile entitlements are missing")
    require(ent.get(TEAM_ID) == team, "profile entitlement team mismatch")
    require(not ent.get("get-task-allow") and not ent.get("com.apple.security.get-task-allow"),
            "profile authorizes debug capability")
    prefix = profile.get("ApplicationIdentifierPrefix")
    require(isinstance(prefix, list) and len(prefix) == 1 and isinstance(prefix[0], str)
            and bool(re.fullmatch(r"[A-Z0-9]{10}", prefix[0])), "profile app ID prefix is missing")
    app_id = f"{prefix[0]}.{bundle}"
    require(allowed(app_id, ent.get(APP_ID)), "profile app ID mismatch")
    groups = ent.get(GROUPS)
    require(isinstance(groups, list) and any(allowed(app_id, x) for x in groups),
            "profile does not authorize the app Keychain group")
    require(isinstance(release, dict) and set(release) == set(CAPABILITIES) | {GROUPS},
            "release entitlement policy includes omitted or unexpected/debug capabilities")
    require(all(release.get(k) is True for k in CAPABILITIES) and release.get(GROUPS) == [],
            "release entitlement policy differs from required sandbox/Keychain policy")
    return {**CAPABILITIES, APP_ID: app_id, TEAM_ID: team, GROUPS: [app_id]}


def validate_profile_input(profile_bytes: bytes, expected_sha256: str) -> None:
    require(bool(re.fullmatch(r"[0-9a-f]{64}", expected_sha256)),
            "reviewed profile SHA-256 is missing or invalid")
    require(bool(profile_bytes) and len(profile_bytes) <= 4 * 1024 * 1024,
            "profile input is empty or exceeds bound")
    require(digest(profile_bytes) == expected_sha256, "reviewed profile hash mismatch")


def command(args: list[str], *, stderr: bool = False, timeout: int = 180) -> bytes:
    result = subprocess.run(args, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
    return result.stderr if stderr else result.stdout


def signing_identity(name: str, keychain: str) -> str:
    require(name.startswith("Developer ID Application: "), "macOS identity must be Developer ID Application")
    output = command(["/usr/bin/security", "find-identity", "-v", "-p", "codesigning", keychain]).decode()
    matches = [m[0].lower() for m in re.findall(r'\b([0-9A-Fa-f]{40})\s+"([^"\n]+)"', output) if m[1] == name]
    require(len(matches) == 1, "signing identity is missing or ambiguous")
    return matches[0]


def read_entitlements(app: Path, arch: str) -> dict:
    raw = command(["/usr/bin/codesign", "--display", "--arch", arch, "--entitlements", "-", "--xml", str(app)])
    return plistlib.loads(raw) if raw.strip() else {}


def macho(path: Path) -> bool:
    with path.open("rb") as stream:
        return stream.read(4) in MACHO


def signed_slice(item: Path, arch: str, temp: Path, team: str, fingerprint: str,
                 certificates: list[bytes], entitlements: dict) -> dict:
    actual = read_entitlements(item, arch)
    require(actual == entitlements, "signed executable/library capability mismatch")
    # Each extraction has its own temporary prefix; no previous certificate can satisfy it.
    with tempfile.TemporaryDirectory(dir=temp, prefix="certificate-") as directory:
        prefix = Path(directory) / "cert-"
        command(["/usr/bin/codesign", "--display", "--arch", arch,
                 f"--extract-certificates={prefix}", str(item)])
        certificate = Path(str(prefix) + "0").read_bytes()
    require(hashlib.sha1(certificate).hexdigest() == fingerprint and certificate in certificates,
            "signed slice certificate mismatch")
    details = command(["/usr/bin/codesign", "--display", "--arch", arch,
                       "--verbose=4", str(item)], stderr=True).decode()
    teams = re.findall(r"(?m)^TeamIdentifier=(.+)$", details)
    require(teams == [team], "signed slice team mismatch")
    return {"entitlements": actual, "team_id": teams[0], "certificate_sha1": fingerprint,
            "certificate_sha256": digest(certificate)}


def sign(app: Path, name: str, profile_path: Path, release_path: Path, team: str,
         bundle: str, expected_profile_sha256: str, keychain: str, output: Path) -> None:
    require(sys.platform == "darwin", "real signing requires macOS")
    identity(team, bundle)
    app = app.resolve(strict=True)
    require(app.is_dir() and app.suffix == ".app", "expected .app bundle")
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    require(info.get("CFBundleIdentifier") == bundle, "app bundle ID mismatch")
    executable = info.get("CFBundleExecutable")
    require(isinstance(executable, str) and PurePosixPath(executable).name == executable
            and executable not in (".", ".."), "invalid main executable")
    main = app / "Contents/MacOS" / executable
    require(not main.is_symlink() and main.is_file(), "main executable missing or symlinked")
    require(macho(main), "main executable is not Mach-O")
    profile_bytes = profile_path.read_bytes()
    validate_profile_input(profile_bytes, expected_profile_sha256)
    release = plistlib.loads(release_path.read_bytes())
    fingerprint = signing_identity(name, keychain)
    require(name.endswith(f"({team})"), "signing identity team mismatch")
    with tempfile.TemporaryDirectory(prefix="aethertune-macos-sign-") as temporary:
        temp = Path(temporary)
        # Decoding is supplementary metadata inspection, never Apple authorization.
        pinned_profile = temp / "reviewed.provisionprofile"
        pinned_profile.write_bytes(profile_bytes)
        decoded = command(["/usr/bin/security", "cms", "-D", "-i", str(pinned_profile)])
        profile = plistlib.loads(decoded)
        entitlements = validate_profile(profile, team, bundle, fingerprint, release)
        entitlements_path = temp / "release.entitlements"
        entitlements_path.write_bytes(plistlib.dumps(entitlements))
        libraries: list[Path] = []
        for path in app.rglob("*"):
            require(path.suffix not in (".appex", ".xpc", ".app"), "unreviewed nested executable bundle")
            if path.is_symlink():
                require(path.resolve().is_relative_to(app), "app symlink escapes bundle")
                continue
            if path.is_file() and path != main and macho(path):
                require("executable" not in command(["/usr/bin/file", "-b", str(path)]).decode(),
                        "unreviewed nested main executable")
                libraries.append(path)
        frameworks = [p for p in app.rglob("*.framework") if not p.is_symlink()]
        embedded = app / "Contents/embedded.provisionprofile"
        require(not embedded.is_symlink(), "embedded profile is a symlink")
        embedded.write_bytes(profile_bytes)
        base = ["/usr/bin/codesign", "--force", "--timestamp", "--keychain", keychain, "--sign", fingerprint]
        # Sign a framework's main library through its bundle, not twice.
        framework_mains = {(p / p.stem).resolve(strict=True) for p in frameworks}
        require(framework_mains.issubset(set(libraries)), "unreviewed framework layout")
        items = frameworks + [p for p in libraries if p not in framework_mains]
        for item in sorted(items, key=lambda p: (-len(p.parts), str(p))):
            command(base + [str(item)])
        command(base + ["--options", "runtime", "--entitlements", str(entitlements_path), str(app)])
        requirement = (f'anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists '
                       f'and certificate leaf[subject.OU] = "{team}" and identifier "{bundle}"')
        command(["/usr/bin/codesign", "--verify", "--all-architectures", "--deep", "--strict",
                 "--verbose=2", "-R", requirement, str(app)])
        require(set(command(["/usr/bin/lipo", "-archs", str(main)]).decode().split()) == ARCHES,
                "main executable is not universal arm64/x86_64")
        main_slices = {arch: signed_slice(app, arch, temp, team, fingerprint,
                                          profile["DeveloperCertificates"], entitlements)
                       for arch in sorted(ARCHES)}
        library_receipts = {}
        for library in libraries:
            arches = set(command(["/usr/bin/lipo", "-archs", str(library)]).decode().split())
            require(arches == ARCHES, "nested code is not universal arm64/x86_64")
            slices = {arch: signed_slice(library, arch, temp, team, fingerprint,
                                         profile["DeveloperCertificates"], {}) for arch in sorted(arches)}
            library_receipts[library.relative_to(app).as_posix()] = {
                "sha256": digest(library.read_bytes()), "slices": slices}
        require(embedded.read_bytes() == profile_bytes, "embedded profile changed during signing")
        receipt = {"schema_version": 1, "team_id": team, "bundle_id": bundle, "certificate_sha1": fingerprint,
                   "profile": {"decoded_plist": decoded.decode(), "sha256": digest(profile_bytes),
                               "reviewed_sha256": expected_profile_sha256,
                               "metadata_is_supplementary": True},
                   "main_executable": main.relative_to(app).as_posix(), "main_sha256": digest(main.read_bytes()),
                   "main_slices": main_slices, "libraries": library_receipts,
                   "release_policy": release, "native_code_requirement_verified": True}
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(receipt, sort_keys=True, indent=2) + "\n")


def validate_archive(archive_path: Path, signing: dict) -> None:
    required = {"schema_version", "team_id", "bundle_id", "certificate_sha1", "profile", "main_executable",
                "main_sha256", "main_slices", "libraries", "release_policy", "native_code_requirement_verified"}
    require(isinstance(signing, dict) and set(signing) in (required, required | {"notarization_input_sha256"})
            and signing["schema_version"] == 1,
            "missing or fake production signing receipt")
    if "notarization_input_sha256" in signing:
        independent_input_digest(signing)
    require(signing["native_code_requirement_verified"] is True, "native code requirement was not verified")
    with zipfile.ZipFile(archive_path) as archive:
        members = archive.infolist()
        require(len({m.filename for m in members}) == len(members), "duplicate macOS ZIP entries")
        targets = [unicodedata.normalize("NFD", m.filename.rstrip("/")).casefold() for m in members]
        require(len(set(targets)) == len(targets), "macOS ZIP filesystem alias collision")
        for member in members:
            p = PurePosixPath(member.filename)
            require(not p.is_absolute() and ".." not in p.parts and "\\" not in member.filename,
                    "unsafe macOS ZIP entry")
            require(member.filename == p.as_posix() + ("/" if member.is_dir() else ""),
                    "noncanonical macOS ZIP entry")
        roots = {PurePosixPath(m.filename).parts[0] for m in members
                 if PurePosixPath(m.filename).parts[0] != "__MACOSX"}
        require(len(roots) == 1 and next(iter(roots)).endswith(".app"), "ZIP must contain one app root")
        root = next(iter(roots)) + "/"
        names = {m.filename for m in members}
        for member in members:
            if not stat.S_ISLNK(member.external_attr >> 16):
                continue
            require(member.filename.startswith(root) and member.file_size <= 4096,
                    "unexpected or oversized archive symlink")
            target = archive.read(member).decode("utf-8")
            require(bool(target) and not target.startswith("/") and "\\" not in target and "\0" not in target,
                    "invalid archive symlink target")
            # Only forward framework aliases are part of this packaging contract.
            # Reject parent traversal before any other link can change its meaning.
            require(".." not in PurePosixPath(target).parts, "archive symlink uses parent traversal")
            resolved = posixpath.normpath(posixpath.join(posixpath.dirname(member.filename), target))
            require(resolved == root[:-1] or resolved.startswith(root), "archive symlink escapes app bundle")
            normalized_link = unicodedata.normalize("NFD", member.filename).casefold() + "/"
            require(not any(name.startswith(normalized_link) for name in targets),
                    "archive symlink is ancestor of a stored entry")
        for member in members:
            parts = PurePosixPath(member.filename).parts
            if parts[0] != "__MACOSX":
                continue
            if member.is_dir():
                require(len(parts) == 1 or parts[1] == root[:-1], "foreign AppleDouble directory")
                continue
            require(len(parts) >= 2 and parts[-1].startswith("._"), "unexpected AppleDouble entry")
            mapped = PurePosixPath(*parts[1:-1], parts[-1][2:]).as_posix()
            require(mapped == root[:-1] or mapped in names or mapped + "/" in names,
                    "AppleDouble entry is not metadata for this app")
            with archive.open(member) as stream:
                header = stream.read(26)
                require(len(header) == 26, "truncated AppleDouble metadata header")
                magic, version, _, count = struct.unpack(">II16sH", header)
                require(magic == 0x00051607 and version == 0x00020000 and 0 < count <= 4096,
                        "invalid AppleDouble metadata header")
                table = stream.read(count * 12)
                require(len(table) == count * 12, "truncated AppleDouble entry table")
                entries = [struct.unpack_from(">III", table, index * 12) for index in range(count)]
                require(len({entry[0] for entry in entries}) == count, "duplicate AppleDouble entry IDs")
                intervals = sorted((offset, offset + length) for _, offset, length in entries)
                require(all(offset >= 26 + count * 12 and end <= member.file_size
                            for offset, end in intervals), "AppleDouble entry exceeds metadata bounds")
                require(all(a[1] <= b[0] for a, b in zip(intervals, intervals[1:])),
                        "overlapping AppleDouble metadata entries")
        files = {}
        actual_libraries = {}
        main_name = signing["main_executable"]
        needed = {"Contents/Info.plist", "Contents/_CodeSignature/CodeResources",
                  "Contents/embedded.provisionprofile", main_name}
        for member in members:
            if not member.filename.startswith(root) or member.is_dir() or stat.S_ISLNK(member.external_attr >> 16):
                continue
            relative = member.filename[len(root):]
            with archive.open(member) as stream:
                head = stream.read(4)
                if relative in needed:
                    files[relative] = head + stream.read()
                elif head in MACHO:
                    sha = hashlib.sha256(head)
                    while chunk := stream.read(1024 * 1024):
                        sha.update(chunk)
                    actual_libraries[relative] = sha.hexdigest()
        require("Contents/_CodeSignature/CodeResources" in files, "missing code signature")
        profile_bytes = files.get("Contents/embedded.provisionprofile")
        require(profile_bytes is not None, "missing embedded macOS distribution profile")
        info = plistlib.loads(files["Contents/Info.plist"])
        require(info.get("CFBundleIdentifier") == signing["bundle_id"], "receipt bundle ID mismatch")
        executable = info.get("CFBundleExecutable")
        require(isinstance(executable, str) and PurePosixPath(executable).name == executable
                and executable not in (".", ".."), "invalid archived main executable")
        main = "Contents/MacOS/" + executable
        require(main == signing["main_executable"] and digest(files[main]) == signing["main_sha256"],
                "signed executable hash mismatch")
        profile_receipt = signing["profile"]
        require(isinstance(profile_receipt, dict) and set(profile_receipt) ==
                {"decoded_plist", "sha256", "reviewed_sha256", "metadata_is_supplementary"}
                and profile_receipt["metadata_is_supplementary"] is True,
                "profile receipt must identify supplementary metadata")
        decoded = profile_receipt["decoded_plist"].encode()
        validate_profile_input(profile_bytes, profile_receipt["reviewed_sha256"])
        require(digest(profile_bytes) == profile_receipt["sha256"], "profile hash mismatch")
        expected = validate_profile(plistlib.loads(decoded), signing["team_id"], signing["bundle_id"],
                                    signing["certificate_sha1"], signing["release_policy"])
        slices = signing["main_slices"]
        require(isinstance(slices, dict) and set(slices) == ARCHES, "both signed slices are required")
        certificates = plistlib.loads(decoded)["DeveloperCertificates"]
        certificate_map = {hashlib.sha1(c).hexdigest(): digest(c) for c in certificates}

        def check_slices(values: dict, entitlements: dict) -> None:
            require(isinstance(values, dict) and set(values) == ARCHES, "both signed slices are required")
            for value in values.values():
                require(isinstance(value, dict) and set(value) ==
                        {"entitlements", "team_id", "certificate_sha1", "certificate_sha256"}
                        and value["entitlements"] == entitlements
                        and value["team_id"] == signing["team_id"]
                        and value["certificate_sha1"] == signing["certificate_sha1"]
                        and value["certificate_sha256"] == certificate_map[signing["certificate_sha1"]],
                        "signed slice capability/certificate/team mismatch")

        check_slices(slices, expected)
        libraries = signing["libraries"]
        require(isinstance(libraries, dict) and set(libraries) == set(actual_libraries),
                "signed library inventory mismatch")
        for name, value in libraries.items():
            require(isinstance(value, dict) and set(value) == {"sha256", "slices"}
                    and value["sha256"] == actual_libraries[name], "signed library hash mismatch")
            check_slices(value["slices"], {})


def file_digest(path: Path) -> str:
    sha = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            sha.update(chunk)
    return sha.hexdigest()


def write_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def independent_input_digest(signing: dict) -> str:
    value = signing.get("notarization_input_sha256") if isinstance(signing, dict) else None
    require(isinstance(value, str) and bool(re.fullmatch(r"[0-9a-f]{64}", value)),
            "independent pre-staple notarization input digest is missing or invalid")
    return value


def bind_app_notarization_input(archive_path: Path, signing_path: Path) -> None:
    """Record actual submitted ZIP bytes after checking the original signing evidence."""
    require(archive_path.name == "aethertune-macos-notarization.zip", "unexpected app submission archive name")
    signing = json.loads(signing_path.read_text())
    require(isinstance(signing, dict) and "notarization_input_sha256" not in signing,
            "app signing receipt already has a notarization input binding")
    before = file_digest(archive_path)
    validate_archive(archive_path, signing)
    require(file_digest(archive_path) == before, "app submission archive changed while checking signed payload")
    signing["notarization_input_sha256"] = before
    write_json(signing_path, signing)


def sign_disk_image(image: Path, name: str, team: str, bundle: str, keychain: str, output: Path) -> None:
    require(sys.platform == "darwin", "real signing requires macOS")
    identity(team, bundle)
    fingerprint = signing_identity(name, keychain)
    require(name.endswith(f"({team})"), "disk image identity team mismatch")
    identifier = bundle + ".disk-image"
    command(["/usr/bin/codesign", "--force", "--timestamp", "--keychain", keychain,
             "--sign", fingerprint, "--identifier", identifier, str(image)])
    requirement = (f'anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists '
                   f'and certificate leaf[subject.OU] = "{team}" and identifier "{identifier}"')
    command(["/usr/bin/codesign", "--verify", "--strict", "-R", requirement, str(image)])
    details = command(["/usr/bin/codesign", "--display", "--verbose=4", str(image)], stderr=True).decode()
    require(re.findall(r"(?m)^TeamIdentifier=(.+)$", details) == [team], "disk image signed team mismatch")
    require(re.findall(r"(?m)^Identifier=(.+)$", details) == [identifier], "disk image signed identifier mismatch")
    with tempfile.TemporaryDirectory(prefix="aethertune-dmg-certificate-") as directory:
        prefix = Path(directory) / "cert-"
        command(["/usr/bin/codesign", "--display", f"--extract-certificates={prefix}", str(image)])
        certificate = Path(str(prefix) + "0").read_bytes()
    require(hashlib.sha1(certificate).hexdigest() == fingerprint, "disk image certificate mismatch")
    write_json(output, {"team_id": team, "identifier": identifier, "certificate_sha1": fingerprint,
                        "certificate_sha256": digest(certificate), "signature_verified": True,
                        "notarization_input_sha256": file_digest(image)})


def notarization_response(response: dict, artifact_name: str, input_sha256: str) -> dict:
    require(isinstance(response, dict) and response.get("status") == "Accepted", "notarization was not Accepted")
    submission = response.get("id")
    require(isinstance(submission, str) and bool(re.fullmatch(
        r"[0-9A-Fa-f]{8}-(?:[0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}", submission)),
        "notarization submission ID is missing or invalid")
    submission = str(uuid.UUID(submission))
    require(bool(re.fullmatch(r"[0-9a-f]{64}", input_sha256)), "notarization input hash invalid")
    return {"artifact": artifact_name, "input_sha256": input_sha256,
            "submission_id": submission, "status": "Accepted"}


def notarize(artifact: Path, key: Path, key_id: str, issuer: str, output: Path, signing_path: Path) -> None:
    require(sys.platform == "darwin", "real notarization requires macOS")
    expected = independent_input_digest(json.loads(signing_path.read_text()))
    before = file_digest(artifact)
    require(before == expected, "notarization artifact differs from independent signed input digest")
    response = json.loads(command(["/usr/bin/xcrun", "notarytool", "submit", str(artifact),
                                  "--key", str(key), "--key-id", key_id, "--issuer", issuer,
                                  "--wait", "--timeout", "20m", "--output-format", "json"], timeout=1300))
    accepted = notarization_response(response, artifact.name, before)
    require("name" not in response or response["name"] == artifact.name,
            "notary submission response name mismatch")
    log = json.loads(command(["/usr/bin/xcrun", "notarytool", "log", accepted["submission_id"],
                             "--key", str(key), "--key-id", key_id, "--issuer", issuer]))
    require(isinstance(log, dict) and log.get("status") == "Accepted" and isinstance(log.get("jobId"), str)
            and str(uuid.UUID(log.get("jobId", ""))) == accepted["submission_id"]
            and log.get("sha256") == before, "notary log job/status/hash mismatch")
    observed_name = log.get("archiveFilename")
    require(observed_name is None or (isinstance(observed_name, str) and len(observed_name) <= 1024
                                     and not any(ord(c) < 32 for c in observed_name)),
            "invalid notary log archive observation")
    accepted["log"] = {"job_id": str(uuid.UUID(log["jobId"])), "sha256": log["sha256"],
                       "status": log["status"], "archive_filename": observed_name}
    require(file_digest(artifact) == before, "notarization input changed during submission")
    write_json(output, accepted)


def validate_notarization(receipt: dict, artifact_name: str, expected_sha256: str) -> None:
    require(isinstance(expected_sha256, str) and bool(re.fullmatch(r"[0-9a-f]{64}", expected_sha256)),
            "independent pre-staple notarization input digest is missing or invalid")
    require(isinstance(receipt, dict) and set(receipt) ==
            {"artifact", "input_sha256", "submission_id", "status", "log"}
            and receipt["artifact"] == artifact_name,
            "notarization receipt is not bound to expected input")
    require(receipt["input_sha256"] == expected_sha256,
            "notarization receipt does not match independent signed input digest")
    log = receipt["log"]
    require(isinstance(log, dict) and set(log) == {"job_id", "sha256", "status", "archive_filename"}
            and log["job_id"] == receipt["submission_id"] and log["sha256"] == receipt["input_sha256"]
            and log["status"] == receipt["status"], "notarization server log binding mismatch")
    observed_name = log["archive_filename"]
    require(observed_name is None or (isinstance(observed_name, str) and len(observed_name) <= 1024
                                     and not any(ord(c) < 32 for c in observed_name)),
            "invalid notary log archive observation")
    notarization_response({"status": receipt["status"], "id": receipt["submission_id"]},
                          receipt["artifact"], receipt["input_sha256"])


def finalize(release_dir: Path, signing_path: Path, image_signing_path: Path,
             app_notarization_path: Path, image_notarization_path: Path) -> dict:
    signing = json.loads(signing_path.read_text())
    app, dmg = release_dir / "aethertune-macos.zip", release_dir / "aethertune-macos.dmg"
    validate_archive(app, signing)
    image_signing = json.loads(image_signing_path.read_text())
    app_notarization = json.loads(app_notarization_path.read_text())
    image_notarization = json.loads(image_notarization_path.read_text())
    receipt = {"schema_version": 2, "app_archive": app.name, "disk_image": dmg.name,
               "app_archive_sha256": file_digest(app), "disk_image_sha256": file_digest(dmg),
               "notarized": True, "stapled": True, "signing": signing,
               "disk_image_signing": image_signing, "app_notarization": app_notarization,
               "disk_image_notarization": image_notarization}
    validate_package_receipt(release_dir, receipt)
    write_json(release_dir / "aethertune-macos-notarization.json", receipt)
    return receipt


def validate_package_receipt(release_dir: Path, evidence: dict) -> None:
    app, dmg = release_dir / "aethertune-macos.zip", release_dir / "aethertune-macos.dmg"
    require(isinstance(evidence, dict) and set(evidence) ==
            {"schema_version", "app_archive", "disk_image", "app_archive_sha256", "disk_image_sha256",
             "notarized", "stapled", "signing", "disk_image_signing", "app_notarization", "disk_image_notarization"}
            and evidence["schema_version"] == 2 and evidence["app_archive"] == app.name
            and evidence["disk_image"] == dmg.name and evidence["notarized"] is True and evidence["stapled"] is True,
            "macOS production receipt requires schema v2 signing and notarization bindings")
    require(evidence["app_archive_sha256"] == file_digest(app) and evidence["disk_image_sha256"] == file_digest(dmg),
            "macOS package hash mismatch")
    signing = evidence["signing"]
    validate_archive(app, signing)
    image_signing = evidence["disk_image_signing"]
    slice_value = signing["main_slices"]["arm64"]
    require(isinstance(image_signing, dict) and set(image_signing) ==
            {"team_id", "identifier", "certificate_sha1", "certificate_sha256", "signature_verified",
             "notarization_input_sha256"}
            and image_signing["signature_verified"] is True
            and image_signing["team_id"] == signing["team_id"]
            and image_signing["identifier"] == signing["bundle_id"] + ".disk-image"
            and image_signing["certificate_sha1"] == slice_value["certificate_sha1"]
            and image_signing["certificate_sha256"] == slice_value["certificate_sha256"],
            "disk image signing identity mismatch")
    validate_notarization(evidence["app_notarization"], "aethertune-macos-notarization.zip",
                          independent_input_digest(signing))
    validate_notarization(evidence["disk_image_notarization"], dmg.name,
                          independent_input_digest(image_signing))


def main() -> None:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="mode", required=True)
    p = sub.add_parser("sign")
    for key in ("app", "profile", "release-entitlements", "output"):
        p.add_argument("--" + key, type=Path, required=True)
    for key in ("identity", "team", "bundle", "profile-sha256", "keychain"):
        p.add_argument("--" + key, required=True)
    p = sub.add_parser("finalize")
    p.add_argument("--release-dir", type=Path, required=True)
    p.add_argument("--signing-receipt", type=Path, required=True)
    p.add_argument("--dmg-signing-receipt", type=Path, required=True)
    p.add_argument("--app-notarization-receipt", type=Path, required=True)
    p.add_argument("--dmg-notarization-receipt", type=Path, required=True)
    p = sub.add_parser("sign-dmg")
    for key in ("image", "output"):
        p.add_argument("--" + key, type=Path, required=True)
    for key in ("identity", "team", "bundle", "keychain"):
        p.add_argument("--" + key, required=True)
    p = sub.add_parser("notarize")
    for key in ("artifact", "key", "output", "signing-receipt"):
        p.add_argument("--" + key, type=Path, required=True)
    for key in ("key-id", "issuer"):
        p.add_argument("--" + key, required=True)
    p = sub.add_parser("bind-app-input")
    for key in ("archive", "signing-receipt"):
        p.add_argument("--" + key, type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.mode == "sign":
            sign(args.app, args.identity, args.profile, args.release_entitlements, args.team, args.bundle,
                 args.profile_sha256, args.keychain, args.output)
        elif args.mode == "sign-dmg":
            sign_disk_image(args.image, args.identity, args.team, args.bundle, args.keychain, args.output)
        elif args.mode == "notarize":
            notarize(args.artifact, args.key, args.key_id, args.issuer, args.output, args.signing_receipt)
        elif args.mode == "bind-app-input":
            bind_app_notarization_input(args.archive, args.signing_receipt)
        else:
            finalize(args.release_dir, args.signing_receipt, args.dmg_signing_receipt,
                     args.app_notarization_receipt, args.dmg_notarization_receipt)
    except (ValueError, OSError, subprocess.SubprocessError, KeyError, TypeError, plistlib.InvalidFileException) as error:
        print(f"macOS production contract failed: {error}", file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
