# Usr cache ownership

Six authored bodies have complete native comparison in both debug modes.
Native CallStatement retains its result in Eval; repeating SetCache(Usr,...)
would release that result before the next callee. Direct caller Usr assignment
and selecting another receiver require a new Usr selection; callee Usr writes
are frame-local. Branch and derived-Usr shapes remain conservative.
