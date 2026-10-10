import importlib.util
import json
from pathlib import Path
import struct
import time
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("daemon_lifecycle", Path(__file__).with_name("daemon-lifecycle.py"))
lifecycle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lifecycle)


class Stream:
    def __init__(self, step=3):
        self.step = step
        self.data = bytearray()
        self.closed = 0

    def write(self, data):
        count = min(self.step, len(data))
        self.data.extend(data[:count])
        return count

    def close(self):
        self.closed += 1


class PipeTests(unittest.TestCase):
    def pipe(self, stream):
        pipe = lifecycle.Pipe.__new__(lifecycle.Pipe)
        pipe.file = stream
        pipe.deadline = time.monotonic() + 10
        return pipe

    def test_partial_writes_produce_one_complete_frame(self):
        stream = Stream(2)
        expected = {"Hello": {"version": 4, "compiler": 123}}
        self.pipe(stream).send(expected)
        size = struct.unpack("<I", stream.data[:4])[0]
        self.assertEqual(size, len(stream.data) - 4)
        self.assertEqual(json.loads(stream.data[4:]), expected)

    def test_zero_progress_and_expired_deadline_are_bounded(self):
        with self.assertRaises(OSError):
            self.pipe(Stream(0)).send("Retire")
        pipe = self.pipe(Stream())
        pipe.deadline = time.monotonic() - 1
        with self.assertRaises(TimeoutError):
            pipe.send("Retire")
        self.assertEqual(pipe.file.data, b"")

    def test_handshake_errors_close_once(self):
        for reply in ({"Hello": {"version": 4, "compiler": 999, "retiring": False}}, {"Rejected": "bad"}, None):
            stream = Stream()
            pipe = self.pipe(stream)

            def receive():
                if reply is None:
                    raise OSError("disconnected")
                return reply

            pipe.receive = receive
            with self.assertRaises((RuntimeError, KeyError, OSError)):
                pipe._hello(123)
            pipe.close()
            self.assertEqual(stream.closed, 1)

    def test_adoption_failure_closes_exact_current_owner(self):
        class Kernel:
            def __init__(self):
                self.closed = []

            def CloseHandle(self, handle):
                self.closed.append(handle)

        pipe = self.pipe(Stream())
        pipe.endpoint = type("Endpoint", (), {"kernel": Kernel()})()
        with patch.object(lifecycle.msvcrt, "open_osfhandle", side_effect=OSError("adoption failed")):
            with self.assertRaises(OSError):
                pipe._adopt_handle(42)
        self.assertEqual(pipe.endpoint.kernel.closed, [42])
        with patch.object(lifecycle.msvcrt, "open_osfhandle", return_value=7), patch.object(lifecycle.os, "fdopen", side_effect=OSError("stream failed")), patch.object(lifecycle.os, "close") as close:
            with self.assertRaises(OSError):
                pipe._adopt_handle(43)
            close.assert_called_once_with(7)
        self.assertEqual(pipe.endpoint.kernel.closed, [42])


if __name__ == "__main__":
    unittest.main()
