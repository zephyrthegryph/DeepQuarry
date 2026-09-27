# Timed work in the object model

Use a `/datum/object_model/task` when a delayed action has a commit step. Override
`check()` for start and commit validation and `complete()` for the synchronous
mutation. Use `C.unchanged(subject)` only for inputs whose revision must stay
unchanged; ordinary task bookkeeping does not advance participant revisions.

`/datum/object_model/task/timed_action` adds live interruption rules. Its
`om_start_timed_action()` helper starts without suspending the caller. The task
owns its timer, observes actor and target movement, equipment and status
changes, and checks all guards again at commit. It also owns the progress bar
and cog. Subtypes put their mutation in `complete()` and may override `check()`.

```dm
/datum/object_model/task/timed_action/example

/datum/object_model/task/timed_action/example/check(datum/object_model/check/task/C, datum/actor, datum/object, datum/implement, list/parameters)
	C.require(!QDELETED(object), "The target is gone.")

/datum/object_model/task/timed_action/example/complete(datum/actor, datum/object, datum/implement, list/parameters)
	var/obj/machinery/M = object
	M.do_the_work()

// In an interaction proc:
om_start_timed_action(/datum/object_model/task/timed_action/example, user, 3 SECONDS, src)
```

For a staged conversion of a synchronous caller, `om_do_after_compat()` accepts
the existing `do_after()` argument shape and returns a boolean. It moves guard
and progress ownership into the task, but the caller still yields in a wait
loop. It is therefore a bridge, not the final API. Convert the caller's code
after `do_after()` into `complete()` before switching to
`om_start_timed_action()`.

The `extra_checks` callback and selected zone have no change signal, so timed
actions check them periodically as well as at commit. New task subtypes should
prefer signal-backed state or `check()` with tracked revisions where available.
Existing `do_after()` remains in place until callers are converted.
