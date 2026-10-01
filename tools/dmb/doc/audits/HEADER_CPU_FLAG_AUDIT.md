# Native header bit 0: CPU property resolution

The native compiler sets header flag `0x00000001` when it resolves the built-in `cpu` property for an evaluated expression. Static compile evidence establishes the trigger; the runtime effect of this flag was not tested.

## Static binary proof

BYOND 516.1687 `byondcore.dll` serializes the global flags word at `0x10430c88` through the header writer near `0x100b4c21`. Its direct bit-zero writer is at `0x101098e5`:

```text
mov eax, [ebp+0x10]
or dword [0x10430c88], 1
or dword [eax], 0x20000
mov eax, 0x4d
ret
```

The resolver switch at `0x101098c6` maps source token `0x259` to that block. The native token-name pointer table starts at `0x1040d624`; entry `0x259` is at `0x1040df88` and names `cpu`. Return value `0x4d` is a built-in property identifier, not the coincidentally numbered `AugLShift` bytecode opcode.

## Native compile observations

All probes compiled with zero errors and zero warnings. Minimal baseline flags are `0x340`.

| Authored expression | Flags |
|---|---:|
| `return world.cpu` | `0x341` |
| `return W:cpu` with untyped argument W | `0x341` |
| `return initial(world.cpu)` | `0x341` |
| `if(0) return world.cpu` | `0x341` |
| Discarded standalone `world.cpu` | `0x340` |
| `return world.vars["cpu"]` | `0x340` |
| Direct O.cpu with `/obj/var/cpu` declaration | `0x340` |
| Local variable named cpu | `0x340` |
| Numeric `a <<= b` | `0x340` |
| `return usr` | `0x340` |

The constant-false branch proves that scanning finalized bytecode is insufficient. The discarded standalone expression proves that a lexical scan is also insufficient: provenance must follow expression resolution and whether the expression is compiled.

Reproduction artifacts are `D:/opendream-diagnostic/header-bit0-probe/`; `probe_all.py` generates and statically compiles nine independent sources and prints their header words. Static decoder scripts are `header_bit0_decode.py` and `header_table_guess.py` in the same diagnostic parent directory. No DreamDaemon was run.

The exporter now preserves `NativeCpuAccess` (optional JSON boolean, false by default). It records authored CPU field resolution before constant branch optimization, suppressing only discarded pure field chains. Computed receiver calls, arithmetic, `nameof`, `initial`, and `issaved` still resolve the CPU property. The portable sixteen-case `fixtures/translation/cpu_access` matrix confirms each exported boolean against the native header bit, including discarded computed receivers versus discarded simple/dynamic receivers. This provenance does not inspect string-based `vars` indexing or custom resolved fields named `cpu`.
