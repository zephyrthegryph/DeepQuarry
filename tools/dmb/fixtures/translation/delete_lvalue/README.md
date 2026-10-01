# Native deletion of lvalues

The native fixture compiles without warnings. For mutable local/argument/global/src/field/indexed storage, native loads the old value, writes a literal PushValNull back to storage, then executes Del on the original value. A numeric local `7` is therefore null on the following read even though deleting the numeric value itself cannot locate its original storage.

Computed field owners and indexed owner/key expressions are evaluated twice: once to load the deletion target and again to clear storage. For indexed effectful calls, native executes owner, key, load, null, owner, key, store, Del. Safe receiver branches separately guard the load and write; failed write guards lead directly to Del, preserving the original deletion target. Synthetic clearing null uses PushVal[0,0], preserving the old value rather than replacing the evaluation register through NullRef.

Readonly const-null globals/fields omit the clearing assignment. Pure typed const receivers disappear; computed const receivers retain their one effectful evaluation and safe const receivers retain guards. Temporary numeric/conditional values have no storage clear. Native rejects multiple arguments to del(a,b); that invalid probe remains outside the portable legal matrix.

The exporter expands the native storage-clear sequence using existing assignment/reference lowering. Paired tests compare all legal authored bodies in debug and nondebug output, with explicit checks for numeric local clearing, four effectful indexed owner/key calls, and readonly stores remaining absent. All 23 authored deletion cases pass the complete paired comparison in both debug modes, including the full package gate. No DreamDaemon was run.

Optional NativeDeleteClearOffsets preserves the clear's safe guard and no-push store offsets after compiler optimization. NativeDeleteSrcOffsets marks direct del(src), whose native Del is followed by End even when further source statements exist. These annotations carry source provenance and add no bytecode operands.
