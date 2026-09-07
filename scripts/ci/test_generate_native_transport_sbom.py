import unittest

from generate_native_transport_sbom import LOCK, generate_bom


class NativeTransportSbomTest(unittest.TestCase):
    def test_real_inventory_is_deterministic_and_checksums_every_registry_package(self):
        raw = LOCK.read_bytes()
        bom = generate_bom(raw)
        self.assertEqual(bom, generate_bom(raw))
        self.assertGreater(len(bom["components"]), 250)
        self.assertTrue(all(component["hashes"][0]["alg"] == "SHA-256" for component in bom["components"]))
        h2 = next(component for component in bom["components"] if component["name"] == "h2")
        self.assertEqual(h2["purl"], "pkg:cargo/h2@0.4.16")

    def test_rejects_unreviewed_sources_missing_hashes_and_duplicates(self):
        root = '[[package]]\nname="rhttp"\nversion="0.1.0"\n'
        dependency = '\n[[package]]\nname="fixture"\nversion="1.0.0"\nsource="registry+https://github.com/rust-lang/crates.io-index"\nchecksum="' + 'a' * 64 + '"\n'
        for content in (
            root,
            root + dependency.replace('checksum="' + 'a' * 64 + '"', ''),
            root + dependency.replace('registry+https://github.com/rust-lang/crates.io-index', 'git+https://example.test/fixture'),
            root + dependency + dependency,
        ):
            with self.subTest(content=content), self.assertRaises(ValueError):
                generate_bom(content.encode())


if __name__ == "__main__":
    unittest.main()
