# Phase 0 pair-access probe

Authored only. Compile, execution, access tracing and results are **pending**.
Use a new scratch directory; never change attributes or contents of existing game outputs.
Root coordinator owns all build/runtime jobs. This fixture needs BYOND 516.1687.

## Controlled execution

1. Copy these five fixture files into a new scratch source directory. Record the
   exact DreamMaker and console dd.exe version and SHA256. Compile access_probe.dme
   with the reference DreamMaker, recording its command, exit status and diagnostics.
2. Preserve the generated DMB/RSC as untouched reference evidence. In separate fresh
   directories prepare a writable-copy control and a read-only-hardlink case. Keep
   their basenames paired. For the latter, set read-only on the PRIVATE reference
   copies before linking; attributes are shared by every hardlink. Never link to
   current game output or a production pair store.
3. Trace dd.exe file opens using Process Monitor File System events, filtered to
   this exact child PID and scratch directory; include CreateFile, WriteFile,
   SetEndOfFile and attribute changes. Keep a raw PML plus exported CSV. Start
   capture before launch and stop it after the child exits. Capture Desired Access,
   disposition, share flags, result and exact path; API imports alone do not prove
   path-specific access. If Procmon unavailable, an equivalent ETW/API trace must
   expose requested access rights; otherwise mark the access result inconclusive.
4. Launch console dd.exe with the fixture DMB, port 0, -trusted and -close. Capture
   stdout/stderr and exit status, with a root-owned external 15-second watchdog.
   The world synchronously tests an embedded text resource, mutates an icon and
   calls fcopy_rsc, logs PHASE0_PAIR_PROBE_OK, then shutdown(). It has no gameplay
   sleeps or background work. Stop ONLY its recorded process tree on timeout.
5. Compare before/after SHA256 of both pair files. Classify all opens of .dmb and
   .rsc by requested rights, even failed requests. Record .dyn.rsc activity
   separately. Dynamic-resource success does not guarantee that a no-client runtime
   materializes a .dyn.rsc; if absent, report that limitation instead of claiming
   the dynamic-resource disk write path was covered.

## Decision

Hardlink compatibility requires BOTH successful read-only startup/static/dynamic
checks AND observed absence of write-capable opens to pair files in the trace.
A write-capable request selects copied writable run slots, regardless of whether
that particular request failed harmlessly. A missing or incomplete trace leaves
copying as the conservative choice. Record engine version and scenario coverage;
this tiny probe cannot establish every future engine or game's access behavior.

Record findings in results.json with status pending/pass/fail/inconclusive, binary
identity, commands, case, exit code, markers, before/after hashes, trace filenames,
observed pair access masks and dynamic-resource limitations. Do not invent results.

cases.json defines later automated publisher tests. Phase 0 supplies the contract
and cases; until the pair publisher exists, crash/concurrency cases remain pending.

## Probe runner

`tools/dmb/phase0/probe-access.ps1` prepares a unique private reference/slot directory
and runs one case. Root coordinator compiles the fixture first and starts Procmon
capture before invoking the runner. Run each case separately with `-Case writable-copy`
or `-Case readonly-hardlink`, `-Dmb <compiled fixture> -OutputRoot <new scratch root>`.
The default engine is `D:/Program Files (x86)/BYOND516/bin/dd.exe`; override explicitly
when pinning another binary. The runner records PID, hashes, command and completion
markers, uses error mode 3, port 0, trusted mode and a maximum 30-second watchdog.
`-Procmon` and `-BackingFile` record tracing locations and print coordinator commands;
they do not start/terminate/export a possibly shared trace. Runtime success remains
`runtime-pass-access-unassessed` until Desired Access evidence is reviewed.
