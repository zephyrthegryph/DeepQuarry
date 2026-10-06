// Tasks (code/engine/kernel/tasks.dm, timed_task.dm): the kernel record of a wait legacy procedural code starts.

/// A task's state.
#define TASK_RUNNING 0
#define TASK_DONE 1
#define TASK_CANCELLED 2

// ---- what a step proc returns (a task's `steps`; a system's step returns STEP_DONE / STEP_YIELD / STEP_PARK too) ----
#define STEP_NEXT 1
#define STEP_DONE 2
#define TASK_STEP_REPEAT 3
#define TASK_STEP_FAIL 4
/// Run this step again after `d` deciseconds.
#define STEP_REPEAT(d) list(TASK_STEP_REPEAT, d)
/// Cancel the task with `reason` (its on_cancel runs).
#define STEP_FAIL(reason) list(TASK_STEP_FAIL, reason)

/// Starts a task: task_start(/datum/task/timed/x, actor, target, var = value, ...). The target is optional (task_start(/datum/task/x, actor)).
#define task_start(task, actor, rest...) task_begin(task, actor, list(rest), src)
