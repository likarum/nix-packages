import hashlib
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("update", Path(__file__).resolve().parents[1] / "scripts/update.py")
u = importlib.util.module_from_spec(spec)
spec.loader.exec_module(u)


class SourceValidation(unittest.TestCase):
    def test_debian_selection_is_package_and_arch_specific(self):
        text = "\n\n".join(f"Package: {name}\nVersion: {version}\nArchitecture: {arch}" for name, version, arch in [
            ("chatgpt", "1.9.0", "amd64"), ("chatgpt", "1.10.0", "amd64"),
            ("other", "9.9.9", "amd64"), ("chatgpt", "8.0.0", "arm64")])
        self.assertEqual(u.select_package(text, "chatgpt", "amd64")["Version"], "1.10.0")
        self.assertEqual(u.select_package(text, "chatgpt", "amd64", "1.9.0")["Version"], "1.9.0")
        with self.assertRaises(ValueError):
            u.select_package(text, "chatgpt", "amd64", "7.0.0")

    def test_signed_index_hash_and_size_are_both_required(self):
        data = b"Package: chatgpt\n"
        digest = hashlib.sha256(data).hexdigest()
        self.assertEqual(u.checked_index(data, digest, len(data)), data.decode())
        for changed, size in [(data + b"evil", len(data)), (data, len(data) + 1)]:
            with self.assertRaises(ValueError):
                u.checked_index(changed, digest, size)

    def test_upstream_cannot_replace_pin_or_downgrade_silently(self):
        old = {"version": "1.2.3", "sources": {"x86_64-linux": {"url": "https://example.org/1.2.3", "hash": "old"}}}
        with self.assertRaises(ValueError):
            u.validate_transition(old, dict(old, version="1.2.2"))
        new = {"version": "1.2.3", "sources": {"x86_64-linux": {"url": "https://example.org/1.2.3", "hash": "changed"}}}
        with self.assertRaises(ValueError):
            u.validate_transition(old, new)
        u.validate_transition(old, old)

    def test_deb_path_cannot_escape_vendor_pool(self):
        for path in ["https://evil.test/chatgpt_1.2.3_amd64.deb", "pool/../chatgpt_1.2.3_amd64.deb",
                     "pool/main/chatgpt_1.2.3_amd64.deb?x", "pool/main/other.deb"]:
            with self.assertRaises(ValueError):
                u.deb_source(u.OPENAI_REPO, "chatgpt", {"Version": "1.2.3", "Filename": path, "SHA256": "a" * 64}, "amd64")


if __name__ == "__main__":
    unittest.main()
