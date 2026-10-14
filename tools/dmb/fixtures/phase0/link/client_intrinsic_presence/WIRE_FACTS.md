# Client presence versus declaration metadata

The captured `probe.dm` was accepted by BYOND 516.1687 with zero errors and
warnings. Its receipt pins the compiler and source hashes. The compiled file is
`E:/dmb-native-v2-phase0/client-intrinsic-presence-control/probe.dmb`.

The frozen `dmb-inspect` tool reports `/client` as class 0 with
`lists_and_procs = [65535, 41, 65535, 65535, 65535, 65535]` and
`overrides = 65535`. There is no variable declaration or override list from which
to decode source modifier flags for `preload_rsc`, `control_freak`, or
`show_verb_panel`. In particular, absence of such a record does **not** prove
flags zero or an initial value of null.

The same file has header flags 3904 (`0xf40`) and `world.control = 0`.
The pinned bootstrap template has header flags 832 (`0x340`). The authored
preload and verb-panel settings are represented by header policy, rather than
ordinary class-variable initializer records. This combined probe certifies
presence and legal instance reads/writes; individual header masks must be
checked against the distinguishing `translation/client_header_probe` fixtures.

Consequently, the intrinsic catalog supplies positive field presence and exact
instance storage only. `EngineSnapshot::declaration_modifiers` must retain
unknown metadata for these absent declaration records. Compiler admission must
project recognized client header settings through a separate typed ABI policy
before ordinary variable initializer classification. Runtime assignment remains
an instance-field operation. No fabricated default or declaration flags should
be used to make the initializer classifier pass.
