# Statement store/reload ownership

The paired fixture contains 19 authored procedures: 16 global callers, two Src methods, and `/datum/observer/Del`. Native and patched OpenDream compilation both succeed without warnings.

A statement assigning a local or argument followed by a reload uses native `SetVar` (0x34), then `GetVar` (0x33). An authored assignment expression uses `SetVarExpr` (0x35). OpenDream formerly fused both source forms into the same Assign instruction, losing this distinction. `NativeStoreReloadOffsets` marks only optimizer-created statement store/reload fusion; explicit expressions stay unmarked.

The distinction affects managed ownership during release of the old local. Native 0x34 moves the stack RHS into frame Eval before the setter; 0x35 retains a copy while the original RHS remains on the stack. The setter replaces the local before releasing its old value. Thus 0x35 adds an observable RHS reference during the old value's synchronous Del callback. This fixture's Del reads `refcount(RHS)` from a shared global.

Static native VM evidence (516.1687):

- 0x34 handler `10145e31` moves the RHS into Eval; 0x35 handler `10145e66` copies it through retain helper `102247b0`.
- Local setter `10130bea` stores the replacement at `10130c11/14`, releases the old local at `10130c19`, then clears Eval.
- RefCount handler `10150c6b` reads the count through `10224e00` and subtracts the operand reference at `10150c86`.
- Datum decrement `101f7840` invokes the zero-reference Del callback through `10132f60` at `101f78c2`; selector id 4 is `Del`.

No DreamDaemon execution was used. Integration assertions compare complete native bodies in both debug modes and independently require the native 34+33 and 35 shapes, the Del RefCount witness, and marked versus unmarked optimized input.
