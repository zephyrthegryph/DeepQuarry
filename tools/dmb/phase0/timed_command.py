"""Run the sampled command unchanged and record its actual execution outcome.

Samply's Windows backend can exit successfully after a failed child, and performs
ETL conversion and symbolication after the child exits. Neither its exit code nor
its wall interval can stand in for the compiler's outcome or execution interval.
The wrapper stays in the sampler's process tree; descendants remain sampled.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import time


def main():
    output = Path(sys.argv[1])
    command = sys.argv[2:]
    if not command or output.exists():
        raise SystemExit("Require a command and a new timing receipt")
    started = time.perf_counter()
    receipt = {"command": command, "cwd": os.getcwd(),
               "started_unix": time.time(), "status": "started"}
    output.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    try:
        stdout_path = output.parent / "compiler.stdout.log"
        stderr_path = output.parent / "compiler.stderr.log"
        with stdout_path.open("wb") as stdout, stderr_path.open("wb") as stderr:
            child = subprocess.Popen(command, stdout=stdout, stderr=stderr)
            receipt["pid"] = child.pid
            code = child.wait()
        receipt.update(status="completed", exit_code=code,
                       ended_unix=time.time(), seconds=time.perf_counter()-started,
                       stdout=str(stdout_path), stderr=str(stderr_path))
    except OSError as error:
        code = 1
        receipt.update(status="failed", error=str(error),
                       ended_unix=time.time(), seconds=time.perf_counter()-started)
    temporary = output.with_suffix(".tmp")
    temporary.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    os.replace(temporary, output)
    raise SystemExit(code)


if __name__ == "__main__":
    main()
