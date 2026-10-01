# Constructor branch entries

Nineteen native/OpenDream paired callers cover branches entering file, sound, icon, generator and literal type constructors. They include named and argument-list forms, effectful ternary branches, and short-circuit values.

Native compilation used a fresh scratch output with BYOND516.1687, and JSON came from the current patched OpenDream exporter; both reported zero warnings. All nineteen complete-body comparisons pass in both debug modes, including named/multiargument conditional controls and dynamic type constructors. These checks retain type pushes and every branch target, and do not normalize missing stack operations.

The game witness is `/proc/log_research`: an early-return branch previously skipped the inserted file-type operand. Prefix insertion now keeps incoming source labels at the inserted type; closed-expression argument analysis also prevents insertion into only the final ternary arm. No runtime was executed.


