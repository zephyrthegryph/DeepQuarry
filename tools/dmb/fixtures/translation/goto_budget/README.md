# Authored goto budget dispatch

Fresh native516.1687 compilation uses JmpLoop(F8) for authored goto in both directions, including an immediately following label. Synthetic ordinary if/switch jumps remain Jmp(0F). Protected authored goto uses TryJmp(12F), preserving exception-frame cleanup and the same budget-dispatch path.

The installed VM F8 path enters10150210, which decrements the execution budget at proc-frame+0x6c and performs scheduling/time checks when it reaches zero. Ordinary Jmp dispatches directly through1015387d. Therefore replacing forward authored goto with ordinary Jmp loses observable budget/scheduling work even though its destination is identical.

NativeGotoOffsets records authored optimized Jump positions; NativeTryGotoOffsets remains dominant in protected bodies. Immediate-jump and related optimizer removal rules preserve marked gotos because even an immediately adjacent goto performs budget work.

The paired matrix covers backward, forward, switch-forward, nested loop gotos, immediate and conditional-adjacent goto, ordinary-if and natural-loop controls, and protected goto. The integration test compares budget-branch kind, direction and destination executable opcode with native in both debug modes. Native0errors0warnings; integration gate pending exporter/schema/lowerer batch. No DreamDaemon executed.
