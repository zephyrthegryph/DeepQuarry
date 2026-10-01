# Native server boot checks

## 2026-09-28: initial paired boot

BYOND 516.1687 DreamDaemon was run against the translated full-game
`deepquarry-iteration4.dmb` and the paired native
`deepquarry-static-ref.dmb`. Both used a separate directory,
`D:/opendream-diagnostic/server-boot-20260928`, copied resource archives,
DLLs, and configuration. Neither ran from the live game directory.

| Check | Translated output | Native reference |
| --- | --- | --- |
| Opens network port | Yes, 49245 | Yes, 57970 |
| Reaches “World loaded” | Yes | Yes |
| NTNet initialization | Read-only write runtime at `build_software_lists`, line 118 | No corresponding runtime |
| Verdigris handshake | ABI mismatch | Same ABI mismatch |
| Fatal shutdown path | Additional read-only write runtime at `world/New`, line 145 | No corresponding runtime |

The library reports ABI `b4fd181f3f0f46a6`, while both compiled worlds expect
`034eab3a3bbb7263`. This is a shared dependency mismatch, and prevents a
successful game startup. Reaching the load message and opening a port do
not establish a successful running game.

Both initial processes were stopped after capturing the results. Logs:

- `D:/opendream-diagnostic/server-boot-20260928/server.log`
- `D:/opendream-diagnostic/server-boot-20260928/native-server.log`

## Matching dependency and repaired translation

A matching Verdigris DLL was built from the frozen game snapshot into
`D:/opendream-diagnostic/server-verdigris-target`. Its SHA256 is
`A649F55DD54B7D8119978E0C40E649A0BCD558CDAC58BE157452E22FC30DA23D`.
Both native and translated worlds then report successful Verdigris loading.
On-disk icons, strings, maps, HTML, interface and sound assets were copied
into the isolated server directory for runtime file access.

The NTNet error was caused by allocating ordinary field ID `0xFFEF`, which
is a native intrinsic slot. Allocation now reserves all of `FFCD..FFF1`,
and operand decoding rejects the unnamed intrinsic holes as ordinary
fields. Two complete native procedure bodies exercise the allocation and
World-output selector boundary. The repaired full-game boot no longer
reports the NTNet read-only error.

The shutdown error was caused by clearing `world` before `del(world)`.
Readonly intrinsics now skip that synthetic assignment. Twelve complete
native procedure bodies verify readonly and mutable deletion behavior in
both debug modes. The core Rust gate passes all 450 tests, and the reserved
intrinsic integration test passes.

The current emitted boot artifact is
`D:/opendream-diagnostic/deepquarry-server-fixed7.dmb`, SHA256
`D80E324CAF766C8DA81A5341885ADA85D0E52691CF325D693A1E8C0D11C6580E`.
All server invocations use `-trusted -invisible`. The console server
`dd.exe` is now used after GUI server launches intermittently stalled
before opening a world.

The native reference and repaired translated output reach Atoms and
Machines initialization and remain alive during observation. This is not
a clean startup: both report power facade errors, while the translated
output additionally reports a null element passed to `power_edit`. An
isolated diagnostic DLL reports that element's index and nearby values;
production and frozen snapshot source files are unchanged.

A local TCP connection to the diagnostic translated server on port 53647
succeeded. This establishes that the server listens; it does not prove
client login, a playable round, or runtime semantic parity.

## Power diagnostic result

Both full-game console runs reached Atoms and Machines initialization and
remained alive. The diagnostic native reference reported no `power_edit`
null-element error. The translated run's first invalid row was a cable
operation: both `d1` and `d2` were null. Other row values, including its
turf coordinates and the three trailing numeric values, were present.

Native and translated minimal live-server probes produced identical
outputs and exited successfully for both ordinary cable construction
(`icon_state = "0-1"`) and a mapped override (`"1-2"`). They cover
`findtext`, `copytext`, `text2num`, mapped string overrides, and resulting
numeric direction fields. This narrows the full-game failure; it does not
resolve it.

A second diagnostic calls `power_key_owner` for the failing row and reads
the owner's fields through BYOND's API. The first affected object is
`/obj/structure/cable/green`: its `icon_state` is `"-"`, and both stored
direction fields are null. This rules out a queue-only read of the wrong
receiver. A minimal color-only child and alpha-only grandchild reproduces
the failure: mapped icon-state overrides work, while a newly created
grandchild loses its inherited `"0-1"` icon state. Numeric defaults remain
correct until parsing the empty string replaces them with null.

The emitter allocated descendants by copying parent class headers before
applying authored built-in defaults to those parents. A parent-first
refresh of inherited headers now repairs this, with twenty-two classes
checked against native output in both debug modes and an exact paired
live cable reproducer. This
also means earlier zero-metadata-difference reports did not establish
runtime parity for inherited built-in defaults. The owner diagnostic log is
`D:/opendream-diagnostic/server-boot-20260928/translated-power-owner.log`.

Diagnostic logs:

- `D:/opendream-diagnostic/server-boot-20260928/translated-power-diagnostic.log`
- `D:/opendream-diagnostic/server-boot-20260928/native-power-diagnostic.log`
- `D:/opendream-diagnostic/cable-runtime-probe/native.log`
- `D:/opendream-diagnostic/cable-runtime-probe/translated.log`
- `D:/opendream-diagnostic/cable-map-runtime-probe/native.log`
- `D:/opendream-diagnostic/cable-map-runtime-probe/translated.log`

All server processes started for these checks were stopped after capture.
Unrelated running servers were left alone. No clean-startup, playable-round,
or client-login claim is made.

## Repaired inherited headers: trusted full-game run

Artifact `D:/opendream-diagnostic/deepquarry-server-header.dmb` has SHA256
`AA9C165CC1E64FB2E44AB93706736D48BDFD9DED2CCB6F96F0BB68176B51298B`.
The console server runs with `-trusted -invisible`, the matching Verdigris
DLL, and the isolated full asset tree. It initializes Atoms and Machines
without the previous null `power_edit` conversion, ABI mismatch, or
readonly-write errors. The shared native power-facade errors remain.
The first attempt then aborts with `memory allocation of 50331648 bytes failed`.
Log: `D:/opendream-diagnostic/server-boot-20260928/translated-header-server.log`.
A fresh native run with `RUST_BACKTRACE=1` and the same trusted settings
completed initialization in 100.575 seconds and remained alive afterward.
Its log is `D:/opendream-diagnostic/server-boot-20260928/native-memory-check.log`.
It still reports the shared power errors and a missing on-disk DMI under
`code/modules/maint_recycler`; successful initialization is not an error-free
or playable-round claim. The native process was stopped after capture.

The identical translated artifact was retried in trusted mode with backtraces.
It completed initialization in **95.9625 seconds** and remained alive afterward,
using about 1.43 GB of private memory. The earlier allocation failure did not
reproduce; its cause remains unproven. The isolated asset tree now includes the
maintenance recycler's on-disk DMI files as well. Retry log:
`D:/opendream-diagnostic/server-boot-20260928/translated-memory-recheck.log`.
The translated process was stopped after capture. These runs establish full
initialization, not a client interaction or playable-round test.

Strict header comparison now includes fields omitted by the earlier
metadata checks. It reveals 42,439 differences in flags, text, names,
layers, directions, and two name defaults. These remain unresolved and
must not be called harmless without evidence. The comparator also aborts
on allocation failure after reporting procedure statistics. Separate bounded
checks subsequently establish zero semantic map differences and identical
payloads, identities, and source timestamps for all 3,856 resource entries.
Archive creation timestamps differ. The cause of the comparator allocation
failure has not been established.

## Final11 trusted boot and lighting discrepancy

The later header and name/text repairs resolve the expanded metadata differences;
see `PARITY_REPORT.md` for the final static results. Artifact
`D:/opendream-diagnostic/deepquarry-final11.dmb` has SHA256
`2DEF9A99D2B702907B0A88422060184C893DBD5AB2E5073AD57D41B998D38AB4`.
Its console server uses `-trusted -invisible` and completes initialization in
213.75 seconds. It remains alive afterward at about 1.43 GB private memory and
is stopped after capture. Log: `translated-final11-server.log` under the isolated
server directory; statistics: `translated-final11-final-stats.json`.

A subsequent comparison finds a translated-only `Cannot read null.x` at
`modules/lighting/lighting_source.dm,270`, also present in final10 and the earlier
translated retry. Earlier summaries that mentioned only shared power errors
missed this error. The instruction location points to `pixel_turf.x` before
the typed corner loops; those loops have matching native null/type filters.
The failing object's identity and the cause of its null pixel turf are still
under investigation. No clean runtime parity claim is supported.

`scripts/compare-runtime-logs.py` compares reported error identities, retaining
counts and source lines. The final11 comparison detects 51 reports of the
translated-only lighting error and exits 1. Comparing the native log to itself
exits 0. Shared power error counts also match in these captures. This check
does not prove gameplay equivalence or identical reporting windows.

### Cause and repair of the lighting error

An isolated native-compiled diagnostic injected before `pixel_turf.x` identifies
711 null pixel-turf events in the translated boot and zero in native. Affected
fire alarms and intercoms have pixel offsets of 32767. Both diagnostic worlds
complete initialization (translated 125.231 seconds, native 121.85 seconds), and
both processes are stopped after capture. Logs are under
`D:/opendream-diagnostic/lighting-runtime-diag/run-{actual,native}`.

Map constant emission incorrectly used unsigned-word `PushInt` for negative
integers. The native VM reads `-26` encoded that way as 65510, which the pixel
setter clamps. `push_map_constant` now emits floating `PushVal` for negative or
wider integers. The semantic comparator had incorrectly interpreted compact
integers as signed 32-bit values, hiding these map differences; it is corrected.

Paired minimal trusted worlds now print identical values and pixel offsets for
negative values, positive values, zero, 65535, and 65536, with no reported runtime
errors. Logs: `lighting-runtime-diag/map-numeric-{native,fixed}.log`. The native
paired regression also requires the old malformed negative encoding to fail
semantic map comparison.

The repaired `deepquarry-final12.dmb` has SHA256
`84BBA39159FD7A58603C51EC2C91B4ABE3E83E302D55B3B64A927B9CD9EC0A03`.
With `-trusted -invisible` and the matched isolated dependencies, it completes
initialization in **101.625 seconds** and remains alive afterward, using about
1.43 GB private memory. Its own server process is stopped after capture.
Log: `server-boot-20260928/translated-final12-server.log`.
`final12-runtime-counts.json` reports **zero translated-only runtime errors**;
the lighting error is absent, and both shared power error counts match native.
The older native capture's missing on-disk DMI predates copying that asset into
the isolated tree. Startup success does not establish playable-round parity.
