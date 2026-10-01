# Direct frame-owner setter boundaries

Fourteen authored native procedure bodies are compared exactly in both debug modes. Controls cover getter-first, direct Src/World setters, explicit caller Src replacement, conditional fallthrough and joins, selection of another or derived owner, and replacement of a managed field whose old value has a Del callback.

Native retains a captured direct Src/World owner after a setter. A flag-only conditional fallthrough still uses that captured owner for a field write; the branch join requires a fresh selector. After that fresh selector, an immediately consecutive direct field getter uses bare Field. Direct `src=O` invalidates the previous context and the first getter selects the new binding.

The lowering extension is limited to SetVar/SetVarExpr direct-root field targets and immediately consecutive GetVar direct-root fields. Getter-only reuse is not carried across intervening operations. Unknown/derived owner selections and control-flow entries remain conservative.

`/datum/holder/Del` reads and replaces the shared OTHER binding, providing an effectful old-field release control. Static native compilation is used; DreamDaemon is not run.
