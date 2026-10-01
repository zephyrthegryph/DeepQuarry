# Native root header boundaries

Seventeen class owners compared against Dream Maker, in both debug modes, including every dedicated appearance header and builtin override. Controls prove:

- Explicit ancestor layer/appearance_flags settings propagate into existing native /obj, /mob, /area, and /turf class records.
- MouseEntered/Exited set 0x800; MouseMove sets 0x80000; MouseWheel sets 0x100000. Authored MouseDown and MouseDrop do not set these header flags.
- Authored direction zero serializes initial direction SOUTH (2).
- Nonzero invisibility clears the normally-visible bit and remains an inherited builtin override.
- Literal area luminosity updates both packed header and builtin override; descendants retain it.

A corrupted direction negative control confirms the strict header comparison detects altered initial appearance.
