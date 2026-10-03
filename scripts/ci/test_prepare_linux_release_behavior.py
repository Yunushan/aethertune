#!/usr/bin/env python3
"""Offline rejection tests for Linux original input boundaries; not runtime acceptance."""
from __future__ import annotations

import copy
import io
import json
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
import prepare_linux_release_behavior as prep


def metadata():
    repository = {"id": prep.REPOSITORY_ID, "full_name": prep.REPOSITORY}
    run = {
        "id": prep.RUN_ID, "run_attempt": 1, "head_sha": prep.SOURCE,
        "head_branch": prep.SOURCE_REF.removeprefix("refs/heads/"),
        "event": "workflow_dispatch", "path": prep.WORKFLOW,
        "status": "completed", "conclusion": "success",
        "repository": repository, "head_repository": repository,
    }
    artifact = {
        "id": prep.ARTIFACT_ID, "name": "aethertune-release-bundle", "expired": False,
        "digest": "sha256:" + prep.OUTER_SHA256, "size_in_bytes": prep.ARCHIVE_BYTES,
        "archive_download_url": f"https://api.github.com/repos/{prep.REPOSITORY}/actions/artifacts/{prep.ARTIFACT_ID}/zip",
        "workflow_run": {"id": prep.RUN_ID, "head_sha": prep.SOURCE,
                         "head_branch": run["head_branch"], "repository_id": prep.REPOSITORY_ID,
                         "head_repository_id": prep.REPOSITORY_ID},
    }
    return artifact, run


def attestation(subjects):
    cert = {
        "subjectAlternativeName": prep.CERT_IDENTITY, "buildSignerURI": prep.CERT_IDENTITY,
        "issuer": "https://token.actions.githubusercontent.com", "buildSignerDigest": prep.SOURCE,
        "sourceRepositoryDigest": prep.SOURCE, "sourceRepositoryRef": prep.SOURCE_REF,
        "sourceRepositoryURI": f"https://github.com/{prep.REPOSITORY}",
        "sourceRepositoryIdentifier": str(prep.REPOSITORY_ID),
        "sourceRepositoryOwnerIdentifier": "24549832", "runnerEnvironment": "github-hosted",
        "runInvocationURI": prep.INVOCATION, "githubWorkflowTrigger": "workflow_dispatch",
    }
    return [{"verificationResult": {
        "signature": {"certificate": cert}, "verifiedTimestamps": [{"type": "Tlog"}],
        "statement": {
            "_type": "https://in-toto.io/Statement/v1", "predicateType": "https://slsa.dev/provenance/v1",
            "subject": [{"name": name, "digest": {"sha256": value}} for name, value in subjects.items()],
            "predicate": {
                "buildDefinition": {
                    "externalParameters": {"workflow": {"path": prep.WORKFLOW, "ref": prep.SOURCE_REF,
                                                       "repository": f"https://github.com/{prep.REPOSITORY}"}},
                    "resolvedDependencies": [{"digest": {"gitCommit": prep.SOURCE},
                                              "uri": f"git+https://github.com/{prep.REPOSITORY}@{prep.SOURCE_REF}"}],
                },
                "runDetails": {"builder": {"id": prep.CERT_IDENTITY},
                               "metadata": {"invocationId": prep.INVOCATION}},
            },
        },
    }}]


class InputBoundaries(unittest.TestCase):
    def test_metadata_rejects_source_attempt_digest_expiry_and_repository_changes(self):
        artifact, run = metadata()
        prep.verify_metadata(artifact, run)
        for field, value in (("run_attempt", 2), ("head_sha", "b" * 40),
                             ("event", "push"), ("conclusion", "failure")):
            altered = copy.deepcopy(run)
            altered[field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                prep.verify_metadata(artifact, altered)
        for field, value in (("expired", True), ("id", 1), ("digest", "sha256:" + "0" * 64),
                             ("size_in_bytes", prep.ARCHIVE_BYTES + 1)):
            altered = copy.deepcopy(artifact)
            altered[field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                prep.verify_metadata(altered, run)
        altered = copy.deepcopy(artifact)
        altered["workflow_run"]["head_repository_id"] = 1
        with self.assertRaises(ValueError):
            prep.verify_metadata(altered, run)

    def test_attestation_rejects_valid_digests_from_other_source_run_or_runner(self):
        subjects = {"RELEASE_MANIFEST.json": prep.MANIFEST_SHA256}
        original = attestation(subjects)
        prep.verify_attestation(original, subjects)
        for field, value in (("sourceRepositoryDigest", "b" * 40), ("buildSignerDigest", "b" * 40),
                             ("sourceRepositoryRef", "refs/heads/main"), ("runnerEnvironment", "self-hosted"),
                             ("runInvocationURI", prep.INVOCATION.replace("/1", "/2"))):
            altered = copy.deepcopy(original)
            altered[0]["verificationResult"]["signature"]["certificate"][field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                prep.verify_attestation(altered, subjects)
        altered = copy.deepcopy(original)
        altered[0]["verificationResult"]["statement"]["predicate"]["runDetails"]["metadata"]["invocationId"] = "other"
        with self.assertRaises(ValueError):
            prep.verify_attestation(altered, subjects)

    def test_attestation_rejects_duplicate_missing_extra_and_changed_subjects(self):
        subjects = {"RELEASE_MANIFEST.json": prep.MANIFEST_SHA256, "linux.deb": prep.DEB_SHA256}
        original = attestation(subjects)
        for kind in ("duplicate", "missing", "extra", "digest"):
            altered = copy.deepcopy(original)
            signed = altered[0]["verificationResult"]["statement"]["subject"]
            if kind == "duplicate":
                signed.append(copy.deepcopy(signed[0]))
            elif kind == "missing":
                signed.pop()
            elif kind == "extra":
                signed.append({"name": "other", "digest": {"sha256": "a" * 64}})
            else:
                signed[0]["digest"]["sha256"] = "a" * 64
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                prep.verify_attestation(altered, subjects)

    def test_graph_lock_binding_rejects_replaced_omitted_or_duplicate_packages(self):
        lock = 'packages:\n  alpha:\n    version: "1.2.3"\n  beta:\n    version: "2.0.0"\nsdks:\n'
        graph = {"root": "application", "packages": [
            {"name": "application", "version": "0.1.0"}, {"name": "alpha", "version": "1.2.3"},
            {"name": "beta", "version": "2.0.0"}]}
        self.assertEqual(2, prep.verify_graph_lock(graph, lock))
        for kind in ("version", "missing", "duplicate"):
            altered = copy.deepcopy(graph)
            if kind == "version":
                altered["packages"][1]["version"] = "2.0.0"
            elif kind == "missing":
                altered["packages"].pop()
            else:
                altered["packages"].append(copy.deepcopy(altered["packages"][1]))
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                prep.verify_graph_lock(altered, lock)

    def test_zip_rejects_traversal_links_duplicates_and_expansion_before_writes(self):
        for kind in ("traversal", "symlink", "duplicate", "oversized"):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                path, output = root / "artifact.zip", root / "release"
                with zipfile.ZipFile(path, "w") as archive:
                    for index in range(19):
                        name = f"subject-{index}.bin"
                        if index == 18 and kind == "traversal":
                            name = "../outside"
                        if index == 18 and kind == "duplicate":
                            name = "subject-0.bin"
                        item = zipfile.ZipInfo(name)
                        if index == 18 and kind == "symlink":
                            item.create_system = 3
                            item.external_attr = (0o120777 << 16)
                        archive.writestr(item, b"payload")
                if kind == "oversized":
                    old = prep.MAX_ZIP_BYTES
                    prep.MAX_ZIP_BYTES = 10
                    try:
                        with self.assertRaises(ValueError):
                            prep.extract_zip(path, output)
                    finally:
                        prep.MAX_ZIP_BYTES = old
                else:
                    with self.assertRaises(ValueError):
                        prep.extract_zip(path, output)
                self.assertFalse(output.exists())
                self.assertFalse((root / "outside").exists())

    def test_tar_rejects_traversal_links_special_files_and_file_ancestors_before_writes(self):
        for kind in ("traversal", "symlink", "hardlink", "fifo", "file-ancestor", "oversized"):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                path, output = root / "bundle.tar.gz", root / "bundle"
                with tarfile.open(path, "w:gz") as archive:
                    item = tarfile.TarInfo("../outside" if kind == "traversal" else "entry")
                    if kind == "symlink":
                        item.type, item.linkname = tarfile.SYMTYPE, "../../outside"
                    elif kind == "hardlink":
                        item.type, item.linkname = tarfile.LNKTYPE, "../../outside"
                    elif kind == "fifo":
                        item.type = tarfile.FIFOTYPE
                    else:
                        item.size = 4
                    archive.addfile(item, io.BytesIO(b"data") if item.isfile() else None)
                    if kind == "file-ancestor":
                        nested = tarfile.TarInfo("entry/child")
                        nested.size = 1
                        archive.addfile(nested, io.BytesIO(b"x"))
                if kind == "oversized":
                    old = prep.MAX_TAR_BYTES
                    prep.MAX_TAR_BYTES = 3
                    try:
                        with self.assertRaises(ValueError):
                            prep.extract_tar(path, output)
                    finally:
                        prep.MAX_TAR_BYTES = old
                else:
                    with self.assertRaises(ValueError):
                        prep.extract_tar(path, output)
                self.assertFalse(output.exists())
                self.assertFalse((root / "outside").exists())


    def test_checksums_reject_incomplete_duplicate_and_replaced_release_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            names = ["RELEASE_MANIFEST.json", "aethertune-linux-x64.deb",
                     "aethertune-linux-x64.tar.gz"] + [f"subject-{index}.bin" for index in range(15)]
            for name in names:
                (root / name).write_bytes(name.encode())
            sums = {name: prep.sha256(root / name) for name in names}
            text = "".join(f"{value}  {name}\n" for name, value in sums.items())
            checksums = root / "SHA256SUMS.txt"
            checksums.write_text(text)
            saved = prep.MANIFEST_SHA256, prep.DEB_SHA256, prep.TARBALL_SHA256
            prep.MANIFEST_SHA256 = sums["RELEASE_MANIFEST.json"]
            prep.DEB_SHA256 = sums["aethertune-linux-x64.deb"]
            prep.TARBALL_SHA256 = sums["aethertune-linux-x64.tar.gz"]
            try:
                self.assertEqual(sums, prep.verify_checksums(root))
                checksums.write_text("\n".join(text.splitlines()[:-1]) + "\n")
                with self.assertRaises(ValueError):
                    prep.verify_checksums(root)
                checksums.write_text(text + text.splitlines()[0] + "\n")
                with self.assertRaises(ValueError):
                    prep.verify_checksums(root)
                checksums.write_text(text)
                (root / "aethertune-linux-x64.deb").write_bytes(b"replacement")
                with self.assertRaises(ValueError):
                    prep.verify_checksums(root)
            finally:
                prep.MANIFEST_SHA256, prep.DEB_SHA256, prep.TARBALL_SHA256 = saved

    def test_tar_regular_payload_reconstructs_bytes_without_source_transformation(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive, output = root / "bundle.tar.gz", root / "bundle"
            with tarfile.open(archive, "w:gz") as stream:
                directory = tarfile.TarInfo("./data")
                directory.type, directory.mode = tarfile.DIRTYPE, 0o755
                stream.addfile(directory)
                item = tarfile.TarInfo("./data/audio.bin")
                item.mode, item.size = 0o644, 4
                stream.addfile(item, io.BytesIO(b"data"))
            prep.extract_tar(archive, output)
            self.assertEqual(b"data", (output / "data/audio.bin").read_bytes())


if __name__ == "__main__":
    unittest.main()

