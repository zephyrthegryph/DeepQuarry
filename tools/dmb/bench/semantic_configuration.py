"""Exact revision-6 semantic command configuration, separate from file identity."""
import hashlib
import json
from pathlib import Path

VERSION = {"version": 516, "build": 1687}
NO_VALUE = {"--no-daemon", "--no-cache", "--exact-inputs", "--progress"}
WITH_VALUE = {"--workers", "--trace", "--record-inputs", "--replay-inputs",
              "--artifact-directory", "--output-store"}


def define(defines, text):
    name, separator, value = text.partition("=")
    if not name or any(not (ch == "_" or "a" <= ch <= "z" or "A" <= ch <= "Z"
                           or index > 0 and "0" <= ch <= "9") for index, ch in enumerate(name)):
        raise ValueError("invalid define name: " + repr(name))
    defines[name] = value if separator else "1"


def command_configuration(project, arguments, sha):
    """Mirror cli.rs definition order and engine option admission; never infer flags."""
    defines = {}
    engine = None
    bootstrap = False
    args = iter(arguments)
    seen = set()
    for option in args:
        if option == "-D":
            text = next(args, None)
            if text is None:
                raise ValueError("-D requires a definition")
            define(defines, text)
        elif option.startswith("-D"):
            define(defines, option[2:])
        elif option == "--engine-template":
            if engine is not None:
                raise ValueError("--engine-template accepts one template")
            text = next(args, None)
            if text is None:
                raise ValueError("--engine-template requires a path")
            engine = Path(text).resolve()
        elif option == "--bootstrap-catalog":
            bootstrap = True
        elif option in NO_VALUE:
            pass
        elif option in WITH_VALUE:
            value = next(args, None)
            if value is None:
                raise ValueError(option + " requires a value")
            if option == "--workers" and (not value.isascii() or not value.isdecimal() or not 0 < int(value) < 2**64):
                raise ValueError("--workers requires a positive usize")
            if option == "--output-store" and option in seen:
                raise ValueError("--output-store accepts one directory")
            seen.add(option)
        else:
            raise ValueError("unclassified semantic option/positional argument: " + str(option))
    if engine is None:
        raise ValueError("benchmark must supply explicit engine-template; implicit paths are not configuration evidence")
    defines.setdefault("DM_VERSION", "516")
    defines.setdefault("DM_BUILD", "1687")
    return {"project": str(project).replace("\\", "/"), "defines": dict(sorted(defines.items())),
            "byond_version": VERSION, "native_engine_template_sha256": sha(engine),
            "bootstrap_catalog": bootstrap}, engine


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def authenticate_pin(pin, configuration, sha):
    if pin.get("semantic_configuration") != configuration:
        raise ValueError("BYOND semantic configuration differs from benchmark project/defines/engine policy")
    evidence = pin.get("configuration_evidence")
    if not isinstance(evidence, list) or not evidence:
        raise ValueError("semantic configuration requires authenticated receipt evidence")
    version_evidence = pin.get("byond_version_evidence")
    if not isinstance(version_evidence, dict) or not isinstance(version_evidence.get("path"), str):
        raise ValueError("BYOND version requires authenticated binary metadata evidence")
    version_path = Path(version_evidence["path"]).resolve()
    if sha(version_path) != version_evidence.get("sha256"):
        raise ValueError("BYOND version evidence hash mismatch")
    version = json.loads(version_path.read_text(encoding="utf-8-sig"))
    if version.get("file_version") != "5.0.516.1687":
        raise ValueError("unsupported BYOND version evidence")
    authenticated = [version_path]
    byond_found = native_found = False
    for item in evidence:
        if not isinstance(item, dict) or not isinstance(item.get("path"), str):
            raise ValueError("invalid configuration evidence")
        path = Path(item["path"]).resolve()
        if sha(path) != item.get("sha256"):
            raise ValueError("configuration evidence hash mismatch")
        receipts = json.loads(path.read_text(encoding="utf-8-sig"))
        receipts = receipts if isinstance(receipts, list) else [receipts]
        for receipt in receipts:
            command = receipt.get("command")
            if not isinstance(command, list) or not command:
                continue
            if receipt.get("producer") == "byond":
                if receipt.get("exit_code") != 0 or receipt.get("timeout") is not False:
                    continue
                args = iter(command[1:])
                defines = {}
                project = None
                for option in args:
                    if option == "-D":
                        text = next(args, None)
                        if text is None:
                            raise ValueError("BYOND evidence -D missing value")
                        define(defines, text)
                    elif option.startswith("-D"):
                        define(defines, option[2:])
                    elif option.startswith("-") or project is not None:
                        raise ValueError("unclassified BYOND evidence option")
                    else:
                        project = option.replace("\\", "/")
                defines.setdefault("DM_VERSION", str(configuration["byond_version"]["version"]))
                defines.setdefault("DM_BUILD", str(configuration["byond_version"]["build"]))
                if project == configuration["project"] and defines == configuration["defines"]:
                    if receipt.get("compiler_sha256") != version.get("compiler_sha256"):
                        raise ValueError("BYOND version evidence does not authenticate receipt compiler")
                    if receipt.get(".dmb_sha256") != pin.get("dmb_sha256"):
                        raise ValueError("BYOND configuration receipt does not pin baseline DMB")
                    byond_found = True
            elif len(command) >= 3 and command[1] == "compile":
                native, _ = command_configuration(command[2], command[3:], sha)
                if native == configuration:
                    native_found = True
        authenticated.append(path)
    if not byond_found or not native_found:
        raise ValueError("configuration evidence must include matching successful BYOND command and native engine policy command")
    return authenticated
