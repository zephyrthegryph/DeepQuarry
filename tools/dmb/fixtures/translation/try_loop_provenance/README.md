# Protected loop branch provenance

Native 516.1687 compiles these nine cases without warnings. Authored `continue` and `goto` inside a protected body use TryJmp; authored `break` uses Catch. An ordinary loop tail keeps JmpLoop.

The installed native VM Try handler at 1015042f..10150485 stores an exception frame's start as the first protected word and its end as the catch destination. TryJmp at 101504dc..10150524 compares **destination minus one** against those ranges, frees exited frames, then enters the same loop-budget path at 10150210 used by JmpLoop. Catch at 1015048a..101504d7 performs the range cleanup and enters ordinary dispatch.

Consequently, a continue to the first protected word removes that exception frame; substituting JmpLoop keeps it. The prefixed case starts its loop later and retains the outer frame. Nested and indexed loops exercise additional frame/iterator structure. The paired test checks native cleanup counts and target/frame relationships in both debug modes; it also guards the ordinary natural-tail opcode. It does not assume unreachable tail layouts must match.

Optional NativeTryContinueOffsets, NativeTryGotoOffsets, and NativeTryBreakOffsets retain authored branch provenance after optimization. They identify existing Jump offsets and change neither opcode widths nor the opcode hash. The lowerer restores native protected handlers before final target relocation. No DreamDaemon execution was used. All nine focused cases pass both debug modes. The full package gate is pending.
