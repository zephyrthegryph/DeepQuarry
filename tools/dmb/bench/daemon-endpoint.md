# Compiler generation endpoint contract

Supervisors ask the exact pinned compiler image for its endpoint:

```powershell
dmbc.exe --daemon-endpoint-json
```

The command emits one JSON object and exits. It does not open a connection,
create a listener, start or retire a daemon. On Unix it also avoids creating
runtime directories. `DMB_DAEMON_NAMESPACE` selects the ordinary validated scope;
unset selects the default scope. Invalid scopes fail rather than selecting a
default or legacy endpoint.

Schema 1, `endpoint_scheme: "compiler-generation-v1"`, contains:

| Field | Meaning |
| --- | --- |
| `protocol_version` | Wire version implemented by this image |
| `compiler_identity` | Full compiler-image identity as 32 lowercase hex digits |
| `namespace` | Exact requested scope, or `null` for default |
| `transport` | `windows-named-pipe` or `unix-socket` |
| `generation_endpoint` | Exact build/query endpoint for this compiler image |
| `discovery_endpoint` | Stable advisory Hello/retirement endpoint only |

`daemon_endpoint.py` is the shared benchmark adapter. It validates the descriptor,
pins the producing image before and after capture, and bounds/reaps the metadata
child. With an existing OwnedJob it admits the child suspended before execution.
It never reproduces SID lookup, endpoint naming or namespace hashes in Python.
Old binaries without this contract, wrong namespaces and unsupported wire
versions are rejected explicitly; there is no legacy pipe fallback.

Metadata is an address recipe, not evidence that a live server is present. The
Windows `Endpoint.probe` still checks `GetNamedPipeServerProcessId` against the
owned process. Direct protocol clients then use the descriptor's exact identity
and version for Hello. Build/query requests use only `generation_endpoint`.
Upgrade controls hold distinct old/new generation addresses while the ordinary
new CLI client initiates retirement through stable discovery. A descriptor does
not prove publication, source correctness, drain coverage or measured performance.

Source-level focused gates: Rust `endpoint_descriptor_`; Python
`test_daemon_endpoint.py` and `test_daemon_lifecycle.py`. Live startup/upgrade and
real-source iteration checks remain separate and require pinned binaries.
