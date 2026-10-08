"""Bounded termination of a benchmark's own Popen handle and child tree."""
import os
import signal
import subprocess


def terminate_owned(process, grace=5):
    receipt = {"pid": process.pid, "tree_error": None, "direct_error": None,
               "wait_error": None, "returncode": process.returncode, "reaped": False}
    try:
        if process.poll() is None:
            if os.name == "nt":
                tree = subprocess.run(
                    ["taskkill", "/PID", str(process.pid), "/T", "/F"],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                    timeout=grace, creationflags=subprocess.CREATE_NO_WINDOW)
                if tree.returncode:
                    receipt["tree_error"] = f"taskkill exited {tree.returncode}"
            else:
                os.killpg(process.pid, signal.SIGKILL)
    except (OSError, subprocess.TimeoutExpired) as error:
        receipt["tree_error"] = str(error)
    finally:
        # Popen.kill uses the owned Windows process handle, not a newly opened
        # PID. A hung/failed taskkill must never bypass this independent fallback.
        try:
            process.kill()
        except OSError as error:
            receipt["direct_error"] = str(error)
        try:
            receipt["returncode"] = process.wait(timeout=grace)
            receipt["reaped"] = True
        except (OSError, subprocess.TimeoutExpired) as error:
            receipt["wait_error"] = str(error)
            receipt["returncode"] = process.returncode
    return receipt
