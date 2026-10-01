# Local statement store ownership

Native explicit assignment expressions retain SetVarExpr35. A statement store
followed by a read emits SetVar34 then GetVar33. The optimized OpenDream bytecode
previously erased this distinction. SetVarExpr keeps the original stack RHS and
retains a second copy before replacing the local; native statement store moves
that ownership instead. The old local's Del observes an extra RHS reference via
refcount(), which reads the raw native reference counter.

Six caller bodies are compared completely in both debug modes; an old local
observer records refcount(global RHS) in Del. No DreamDaemon execution is used.
