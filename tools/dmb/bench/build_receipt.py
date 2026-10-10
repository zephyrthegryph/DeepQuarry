"""Optional exact executable provenance; never benchmark acceptance authority."""
import json
from pathlib import Path


def authenticate(path, executable, sha):
    path = Path(path).resolve()
    if path.stat().st_size > 1024 * 1024:
        raise ValueError("build receipt exceeds 1 MiB")
    before = sha(path)
    value = json.loads(path.read_text(encoding="utf-8"))
    if sha(path) != before:
        raise ValueError("build receipt changed during admission")
    if type(value.get("exit_code")) is not int or value["exit_code"] != 0:
        raise ValueError("build receipt does not prove successful build")
    digest = sha(executable)
    if value.get("binary_sha256") != digest:
        raise ValueError("build receipt executable SHA mismatch")
    level = value.get("dmbc_opt_level")
    units = value.get("dmbc_codegen_units")
    if level is not None and (type(level) is not int or level not in (1, 2, 3)):
        raise ValueError("invalid build receipt optimization level")
    if units is not None and (type(units) is not int or units <= 0):
        raise ValueError("invalid build receipt codegen units")
    for field in ("lto", "acceptance_profile"):
        if field in value and type(value[field]) is not bool:
            raise ValueError("invalid build receipt " + field)
    return {"path": str(path), "sha256": before, "compiler_sha256": digest,
            "commit": value.get("commit"), "dmbc_opt_level": level,
            "dmbc_codegen_units": units, "lto": value.get("lto"),
            "declared_acceptance_profile": value.get("acceptance_profile"),
            "benchmark_acceptance_admitted": False,
            "scope": "successful-build receipt matched to exact executable bytes"}
