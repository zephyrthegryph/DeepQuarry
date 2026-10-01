# Switch default transfer operations

Native switch defaults containing authored continue/goto must enter the transfer instruction, including its loop-budget or protected-region cleanup effect. Synthetic table-routing jumps can be folded into destinations. Seven native table handlers now retain authored transfers rather than consuming their offsets.

Five fresh native pairs cover range/exact continues, string goto, protected continue, and a synthetic-default negative. Debug modes preserve keyed case/default path instructions, scalar operands, transfer kind and destination instruction/operands. The bounded test follows plain routing jumps and stops at loop increment, budget transfer, protected cleanup or return; it does not relax the production comparer. Both debug modes passed focused direct tests.
