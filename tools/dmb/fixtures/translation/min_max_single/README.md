# Single-argument min/max

Native516.1687 usesD0/D1 for ordinary single arguments andA5/A6[count] for multiple arguments. The paired matrix includes generic/list parameters, number/null/text, empty lists, effectful proc-returned lists and two arguments. Native zero-argument min() rejects the source (expected1or more argument).

Static dispatch table10154278 routesA5 to1015317d andA6 to10153250. With count1 they pop one tagged value then immediately return it (101531d6 /101532a9), without reducing a list. D0/D1 dispatch10153323/1015333f calls helpers101679d0/101670e0; list-like values are enumerated using101646a0 and1015f500 and compared with10167ad0/101671e0. Non-list scalar values return unchanged. Thus substitutingA5[1] forD0 returns the list itself rather than its minimum; scalar-only examples happen to agree.

Lowering now selectsD0/D1 for ordinary single arguments as well as its existing arglist path; multiple counts remain unchanged. Tests require exact opcodes and complete normalized native bodies in debug and nondebug outputs. No DreamDaemon was run.
