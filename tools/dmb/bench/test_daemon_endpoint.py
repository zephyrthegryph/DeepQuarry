import json
import subprocess
import unittest
from unittest.mock import patch

import daemon_endpoint as E


def metadata(namespace=None, identity="1" * 32):
    # Deliberately opaque addresses: Python consumes them without naming/hash logic.
    return dict(schema_version=1, endpoint_scheme="compiler-generation-v1",
        protocol_version=5, compiler_identity=identity, namespace=namespace,
        transport="windows-named-pipe", generation_endpoint=r"\\.\pipe\opaque-generation",
        discovery_endpoint=r"\\.\pipe\opaque-discovery")


class Child:
    def __init__(self, stdout, status=0, stderr=b"", timeout=False):
        self.stdout = stdout
        self.returncode = status
        self.stderr = stderr
        self.timeout = timeout
        self.killed = False
        self.reaped = False

    def communicate(self, timeout):
        if self.timeout and not self.killed:
            self.returncode = None
            raise subprocess.TimeoutExpired("descriptor", timeout)
        self.reaped = True
        return self.stdout, self.stderr

    def poll(self):
        return self.returncode

    def kill(self):
        self.killed = True
        self.returncode = -9


class EndpointTests(unittest.TestCase):
    def test_default_and_scoped_names_remain_opaque_exact_compiler_answers(self):
        for namespace in (None, "iteration-example"):
            value = metadata(namespace)
            self.assertIs(E.validate_descriptor(value, namespace), value)
            self.assertEqual(value["generation_endpoint"], r"\\.\pipe\opaque-generation")

    def test_legacy_protocol_wrong_scope_or_partial_descriptor_cannot_fallback(self):
        for change in ({"schema_version": 0}, {"protocol_version": 4},
                       {"endpoint_scheme": "legacy"}, {"namespace": "wrong"},
                       {"compiler_identity": "123"}, {"transport": "tcp"},
                       {"generation_endpoint": "127.0.0.1:1"},
                       {"generation_endpoint": metadata()["discovery_endpoint"]}):
            value = metadata(); value.update(change)
            with self.assertRaises(ValueError):
                E.validate_descriptor(value, None)
        value = metadata(); del value["namespace"]
        with self.assertRaises(ValueError):
            E.validate_descriptor(value, None)

    def test_loader_pins_image_and_selects_explicit_namespace_without_autostart(self):
        for namespace in (None, "iteration-example"):
            child = Child(json.dumps(metadata(namespace)).encode())
            with patch.object(E, "file_sha256", return_value="a" * 64) as digest, patch.object(E.subprocess, "Popen", return_value=child) as popen:
                value = E.load_descriptor("compiler.exe", "a" * 64, namespace,
                    environment={"DMB_DAEMON_NAMESPACE": "inherited", "EXAMPLE": "preserved"})
            self.assertEqual(value, metadata(namespace))
            self.assertEqual(popen.call_args.args[0], ["compiler.exe", "--daemon-endpoint-json"])
            environment = popen.call_args.kwargs["env"]
            self.assertEqual(environment.get("DMB_DAEMON_NAMESPACE"), namespace)
            self.assertEqual(environment["EXAMPLE"], "preserved")
            self.assertEqual(digest.call_count, 2)
            self.assertTrue(child.reaped)

    def test_legacy_binary_and_changed_image_fail_without_starting_another_process(self):
        for child in (Child(b"", 2, b"expected analyze or compile"), Child(b"{}"), Child(b"not-json")):
            with patch.object(E, "file_sha256", return_value="a" * 64), patch.object(E.subprocess, "Popen", return_value=child) as popen:
                with self.assertRaises((RuntimeError, ValueError)):
                    E.load_descriptor("compiler.exe", "a" * 64)
                self.assertEqual(popen.call_count, 1)
        with patch.object(E, "file_sha256", return_value="b" * 64), patch.object(E.subprocess, "Popen") as popen:
            with self.assertRaises(ValueError):
                E.load_descriptor("compiler.exe", "a" * 64)
            popen.assert_not_called()

    def test_descriptor_timeout_kills_and_reaps_only_owned_child(self):
        child = Child(b"", timeout=True)
        with patch.object(E, "file_sha256", return_value="a" * 64), patch.object(E.subprocess, "Popen", return_value=child):
            with self.assertRaises(subprocess.TimeoutExpired):
                E.load_descriptor("compiler.exe", "a" * 64, timeout=1)
        self.assertTrue(child.killed)
        self.assertTrue(child.reaped)


if __name__ == "__main__":
    unittest.main()
