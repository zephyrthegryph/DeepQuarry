# Finite native callback extension receipts

DreamMaker 516.1687 compile-only controls captured 2026-10-07. No runtime was
launched. Raw logs/DMBs stay outside Git at
`D:/dmb-native-v2-phase0/callback-abi-controls-2/`.

`control.dme`: 28 authored overrides, zero errors/warnings. Each authored
procedure was decoded individually: flags 4, source kind 0/parameter 255,
display name equal to its exact spelling, absent description/category and
extended flags. Owner/name pairs:

- `/atom`: Cross, Crossed, Uncross, Uncrossed, MouseMove, MouseWheel.
- `/atom/movable`: Bump, Move.
- `/client`: Export, MouseMove, MouseWheel, Northeast, Northwest, Southeast,
  Southwest, Center.
- `/world`: Export, IsBanned, Profile, Tick.
- `/area` and `/turf`: Enter, Entered, Exit, Exited.

Decoded class records put all these authored members in procedure lists. In
particular, `/client` has verb-list ID 65535 and a procedure list containing the
directional overrides. OpenDream's `IsVerb` annotation is not a native namespace
receipt. `explicit-verbs.dme` rejects Northeast, Center and Crossed with three
"conflicts with built-in proc" errors; explicit namespaces are not rewritten.

`value-types.dme`: eight authored overrides, zero errors/warnings: `/icon`
Insert/New, `/image` New, `/matrix` Add/Multiply/New/Subtract, `/sound` New. Their
authored body records have the same header framing above. Retained native
constructor records can share the same path; all matching records were inspected
and the empty authored bodies identified separately in `value-types-records.log`.

`list-rejected.dme` is intentionally invalid: five "list-derived types are not
supported" errors. List Add/Copy/Insert/New/Remove are excluded from receipts.

These positive receipts join the earlier callback/New/Del controls in one
`native_callbacks` inventory shared by engine presence, ABI preparation and the
receiver-method catalog. Exact pair contents and namespace enter both engine and
ABI policy identities. The inventory does not infer signatures, parameter
defaults, wire procedure IDs, or absence of unknown names. Source signatures
remain authored facts; unobserved callback names and owners stay unsupported.
