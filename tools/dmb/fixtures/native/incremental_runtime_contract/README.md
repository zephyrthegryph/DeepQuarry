# Incremental runtime contract

This standalone corpus declares eleven exact runtime values: inherited instance
default, parent call with omitted and explicit arguments, global procedure
argument defaults, global initializer, first and second procedure-static calls,
and a field/procedure structural extension, plus the numeric contents of an
embedded resource, plus separately observed inherited/own defaults of a newly added type. It has no game boot or FFI. Runtime directories contain only
the DMB and RSC; the resource observation must come from the archive.

The sixteen revisions are initial, unchanged, body edit, inherited default edit,
argument default edit, procedure-static initializer edit, global initializer
edit, parent change and restoration, field/procedure addition, runtime field
initializer replacement, removal of that initializer/field/procedure, resource replacement and an unchanged
resource build, followed by adding and deleting a new subtype. The added subtype is instantiated through a typed local and must report inherited value 9 and own value 31; deletion restores the zero-valued observer without retaining a reference to the removed type. All sixteen revisions passed the paired run recorded in `phase0/publication_integration_20261011.json` for compiler commit `f5a9e36195`; existing fourteen-revision receipts remain historical evidence for their original nine markers. Edits are cumulative and identify
one exact source site. `scenarios.json` contains the expected values for each
revision. Both compilers returning the same wrong result is a failure.

For every revision the helper compiles pinned BYOND 516.1687, retained native
through its owned production daemon, and fresh native with `--no-daemon
--no-cache`. Retained and fresh use the same current source path and two workers.
The helper independently acquires both exact native generations and checks
their DMB/RSC SHA-256 byte equality. Three separate DD worlds must match the
declared ordered markers and report no runtime errors. Each world starts anew;
the compiler retains state, not the runtime's procedure-static variables.
Native worlds run on independent writable copies of the authenticated acquired
pair. DreamDaemon may modify a runtime archive; acquisition and immutable store
hashes must still match after execution. Runtime archive hashes are recorded
separately and are not treated as immutable compiler output.

Run after the parent coordinator releases build/measurement holds:

```powershell
python tools/dmb/fixtures/native/incremental_runtime_contract/run.py `
  --native E:/path/to/frozen/dmbc.exe --native-sha256 <sha256> `
  --template tools/dmb/fixtures/native_template.bin --template-sha256 <sha256> `
  --dm 'D:/Program Files (x86)/BYOND516/bin/dm.exe' --dm-sha256 <sha256> `
  --dd 'D:/Program Files (x86)/BYOND516/bin/dd.exe' `
  --dd-sha256 2e3815875c4dcf3c50de70c1c6e017849efe8697c428f02ab9ee77c306c8abf0
```

All four input pins and committed source/manifest/scenario hashes are checked
before and after. Owned source copies use UTF-8 LF lines; each revision records
their actual source and resource SHA-256. There is no compiler fallback in this helper. It refuses
a pre-existing account daemon and verifies its own daemon PID before/after every
native compile. Retained clients disable autostart. It leaves foreign daemons
untouched if ownership changes.

The total cohort is bounded to 300 seconds, including the daemon lifetime.
Individual native compiles cannot exceed 300 seconds; BYOND compilation,
acquisition and DD runs are capped at 30 seconds, with daemon startup capped at
20 seconds. Each trusted DD child inherits Windows error mode 3 to suppress
critical-error/crash dialogs; the parent mode is restored. Registered owned
children share a sampled 4GB private-memory budget. Sampling is every 200ms and
does not prove a strict peak or cover unregistered descendants.

Only owned children are reaped on failure or completion. Acquired artifacts,
runtime logs and the receipt remain in the new E: output directory. Successful
cleanup is required for a passing receipt. `complete` refers to this corpus;
`acceptance_profile` stays false. This does not establish full DM unit-test,
six-worktree concurrency, gameplay or performance acceptance.

Focused helper checks (no compilers or DD):

```powershell
python tools/dmb/fixtures/native/incremental_runtime_contract/test_run.py
```

Validated capture: all 14 revisions passed with immutable native compiler
`d105b4c75a` (SHA256
`6cdc14ecd339ad81baa53be83fc775a42ab652d70e5ca92d4c232a884c6777d8`)
and pinned BYOND 516.1687. All three runtime oracles matched their declared
values, no runtimes occurred, and each retained DMB/RSC matched fresh bytes.
Receipt: `E:/dq-cache/dmb-incremental-runtime-contract/d6efec759d8142f7ac48cbec55707aee/receipt.json`.
The owned daemon was reaped; sampled registered private peak was 79.6 MB.
This is a focused tiny corpus, not a DeepQuarry timing or full-suite gate.
An earlier attempt stopped when BYOND rejected `text2num` in a declaration;
that invalid fixture was replaced with a runtime list initializer.
