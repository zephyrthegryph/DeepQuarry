"""Exact read-only endpoint contract supplied by the pinned compiler binary.

Naming, current-user identity and namespace hashing remain Rust responsibilities.
Legacy binaries are unsupported here: a missing/malformed descriptor never falls
back to an older pipe or permits autostart/retirement on a guessed endpoint.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

SCHEMA_VERSION = 1
ENDPOINT_SCHEME = "compiler-generation-v1"
PROTOCOL_VERSION = 5


def validate_descriptor(value, namespace, transport="windows-named-pipe"):
    if not isinstance(value, dict):
        raise ValueError("compiler endpoint descriptor must be an object")
    required = {"schema_version", "endpoint_scheme", "protocol_version", "compiler_identity",
                "namespace", "transport", "generation_endpoint", "discovery_endpoint"}
    if not required.issubset(value):
        raise ValueError("incomplete compiler endpoint descriptor; no legacy fallback")
    if (type(value.get("schema_version")) is not int or value["schema_version"] != SCHEMA_VERSION
            or value.get("endpoint_scheme") != ENDPOINT_SCHEME):
        raise ValueError("unsupported compiler endpoint descriptor; legacy endpoints are not admitted")
    if type(value.get("protocol_version")) is not int or value["protocol_version"] != PROTOCOL_VERSION:
        raise ValueError("unsupported daemon protocol version; no legacy fallback")
    if value.get("namespace") != namespace:
        raise ValueError("compiler endpoint namespace differs from requested scope")
    identity = value.get("compiler_identity")
    if not isinstance(identity, str) or re.fullmatch(r"[0-9a-f]{32}", identity) is None:
        raise ValueError("compiler endpoint identity must be full lowercase hexadecimal")
    if value.get("transport") != transport:
        raise ValueError("compiler endpoint transport is unsupported by this supervisor")
    addresses = []
    for key in ("generation_endpoint", "discovery_endpoint"):
        address = value.get(key)
        if not isinstance(address, str) or not address or len(address) > 1024 or "\0" in address:
            raise ValueError("invalid compiler endpoint address: " + key)
        if transport == "windows-named-pipe" and not address.startswith("\\\\.\\pipe\\"):
            raise ValueError("compiler endpoint is not a local Windows named pipe")
        addresses.append(address)
    if addresses[0] == addresses[1]:
        raise ValueError("generation and discovery endpoints must have distinct roles")
    return value


def file_sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_descriptor(executable, expected_sha256, namespace=None, *, environment=None,
                    owned_job=None, timeout=10):
    """Read metadata from that image only; never connect/start/retire a server."""
    executable = Path(executable)
    if file_sha256(executable) != expected_sha256:
        raise ValueError("compiler image changed before endpoint metadata capture")
    env = dict(os.environ if environment is None else environment)
    if namespace is None:
        env.pop("DMB_DAEMON_NAMESPACE", None)
    else:
        env["DMB_DAEMON_NAMESPACE"] = namespace
    flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
    if owned_job is not None:
        flags |= 0x4  # Existing owned Windows Job admits suspended children.
    child = subprocess.Popen([str(executable), "--daemon-endpoint-json"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, creationflags=flags)
    try:
        if owned_job is not None:
            owned_job.add(child)
            owned_job.resume(child)
        stdout, stderr = child.communicate(timeout=timeout)
    except BaseException:
        if child.poll() is None:
            child.kill()
        child.communicate(timeout=5)
        raise
    if child.returncode != 0:
        message = stderr[:2048].decode("utf-8", errors="replace").strip()
        raise RuntimeError("compiler does not provide supported endpoint metadata; legacy endpoints are not admitted: " + message)
    if len(stdout) > 16384:
        raise ValueError("compiler endpoint descriptor exceeds metadata limit")
    if file_sha256(executable) != expected_sha256:
        raise ValueError("compiler image changed during endpoint metadata capture")
    try:
        descriptor = json.loads(stdout.decode("utf-8"))
    except (UnicodeError, json.JSONDecodeError) as error:
        raise ValueError("invalid compiler endpoint JSON; no legacy fallback") from error
    return validate_descriptor(descriptor, namespace)
