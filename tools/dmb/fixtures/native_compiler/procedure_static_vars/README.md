# Procedure-static vars footer

Pinned BYOND 516.1687 compile-only capture; SHA was checked before and after.
No DreamDaemon was run. `capture.json` authenticates the source and output.

`static_vars` reads shared VarID67, and `static_other` reads shared VarID68.
Both records have kind62. The global declaration footer contains `(68,1)` but
does not contain VarID67. The slot named `vars` must remain available to the
procedure while being omitted from that footer. Local and built-in vars reads
are included as controls; this fixture does not prove arbitrary shadowing.
