# Pinned native vision macro controls

Compiler: BYOND 516.1687, exact executable SHA-256
`8cac7e8bd48219f8a7fb622535a1ce1a914d0a9a3e909bc9ceb84b3074709dc0`.
Hidden sequential compile-only controls; no DreamDaemon run. Raw logs, binaries,
and decoded code remain outside Git at
`D:/dmb-native-v2-phase0/vision-constant-controls`.

`positive.dme`: 0 errors/warnings. Each root and `/datum` procedure returns
`PushInt VALUE; Ret; End`, with these observed values:

| Macro | Value |
|---|---:|
| SEE_BLACKNESS | 1024 |
| SEE_INFRA | 64 |
| SEE_MOBS | 4 |
| SEE_OBJS | 8 |
| SEE_PIXELS | 256 |
| SEE_SELF | 32 |
| SEE_THRU | 512 |
| SEE_TURFS | 16 |

`define.dme`: 0 errors/warnings, explicit replacement returns `PushInt 7`.
`undef.dme`: 0 errors/warnings. Root bare SEE_BLACKNESS is a runtime global
`GetVar [65499,18]`, not a folded literal.
`qualified.dme`: one expected error, `returnglobal.1024: undefined var`, proving
initial substitution also occurs after the authored `global.` selector.
`qualified-undef.dme`: 0 errors/warnings; qualified global reads slot 18.
`shadow.dme`: 0 errors/warnings; after undef, authored `/datum/shadow` field is
legal and its read emits a Src field selector. Root read still uses global slot18.

These receipts certify the eight initial macro replacements. They do not certify
immutable semantic constants after undef, or completeness of native macro names.
No engine/runtime slot identity is inferred for the new frontend from these IDs.
Existing TRUE/FALSE handling remains separate.
