Pinned BYOND 516.1687 compile-only local sized-array initializer matrix.

See receipt.json for exact compiler/source/output hashes and bounded child execution. Positive captures preserve full native DMB bytes; rejected cases preserve diagnostics. No runtime was executed. Opcode behavior requires decoding and producer comparison before implementation.

Decoded `/proc/probe` words are preserved in decoded.json with exact frozen inspector hash. Explicit RHS cases store the RHS in Local0 before evaluating dimensions and allocating a list; the subsequent allocation has no SetVar Local0. Implicit cases allocate then store Local0. The nonliteral dimension reads Arg0 once after RHS assignment. These are executable encoding observations, not runtime observations; stack cleanup and general effectful dimension behavior require existing opcode contract/producer verification.
