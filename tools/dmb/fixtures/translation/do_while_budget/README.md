# Authored do/while budget checks

Native F9 JnzLoop checks the loop budget after evaluating its flag on both outcomes. The installed516.1687 VM dispatch table10154278 maps F9 to10150284: a true flag selects the backward target, a false flag retains fallthrough, and both paths reach the budget decrement1015029f. Jz11 bypasses that decrement; splitting the tail into Jz(exit) and F8(backedge) therefore omits the final false budget check.

Sixteen native paired callers cover effectful conditions, nested loops, continue, exception frames, an outer iterator, protected continue, and negative authored goto/ordinary while controls. Constantfalse/null conditions have no native tail; constanttrue uses onlyF8. Constantnull outside the loop reads its hidden binding instead of an authored null reader. Native compilation was fresh with zero warnings; no runtime was executed. All sixteen complete native bodies and explicit budget-opcode controls pass in both debug modes against the fresh9:52:03 library and actual rebuilt exporter JSON. Malformed annotation controls require a following backward jump and its exact false exit boundary.


Seventeen complete bodies now pass, including a constant-true loop whose authored continue goes directly to its body rather than through a second budgeted natural backedge. An eighteenth all-path continue/break control checks the reachable budget graph; native retains an unreachable natural tail that source optimization removes. The test requires exactly one reachable F8 and rejects a reachable F8-to-F8 sequence.
