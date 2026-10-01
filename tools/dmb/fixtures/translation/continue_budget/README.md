# Continue and synthetic loop joins

Fresh native516.1687 probes distinguish authored continue from compiler-generated if/else joins. A while-loop if/else join targeting the final loop-back instruction uses ordinary Jmp(0F), then the natural loop back uses JmpLoop(F8). The former heuristic incorrectly emitted F8 for both, performing an extra budget decrement.

Authored continue uses F8 even when it jumps forward to a for-loop increment. Protected continue retains TryJmp(12F).

NativeContinueOffsets is always an array in current exports: [] proves there is no authored continue at any offset. Legacy missing metadata remains None and retains the older heuristic. The lowerer uses source provenance for current exports and keeps the natural backward-loop dispatch unchanged.

The paired matrix covers while if/else joins with/without a following decrement, forward for-loop continue and backward while-loop continue. It compares budget-branch counts, direction and executable destination against native in both debug modes. Native0errors0warnings; focused/full gates pending combined source batch.
