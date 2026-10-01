# Managed call result ownership

Native/OD compiler-only pair; no DreamDaemon run. `probe.dm` returns lists and
objects through global and method calls, with positional, named, arglist and
safe receiver forms. Every discarded OD call ends in `Pop` (`0x51`), while
returned call forms end in `Return` (`0x10`). Method calls use authored native
method selector opcode `0xaa`; ordinary non-safe receivers use marker `0xa3`.

The paired native discarded call uses `CallStatement` (`0x2a`) followed by a
skipped `Pop`; returned calls use `Call` (`0x29`). These have the same invocation
but distinct managed return lifetime: the statement form retains its owned
return in the evaluation slot until replacement, while `Call; Pop` immediately
releases it. See `../../../STATIC_SELECTOR_EVIDENCE.md` for the exact VM trace.
This fixture supports choosing native statement lowering; it does not justify
normalizing their lifetime difference away.
