// Context escape: a pooled act may be held in a local for the trigger, never stored.
/obj/machinery/lamp/proc/escape_clean(datum/act/op/A)
	var/datum/act/op/same = A
	var/list/snap = A.snapshot()
	queue = snap
	saved = snap
	return same.held

/obj/machinery/lamp/proc/escape_field(datum/act/op/A)
	saved = A
	return TRUE

/obj/machinery/lamp/proc/escape_list(datum/act/op/A)
	var/list/L = list(A)
	queue = L
	return TRUE

/obj/machinery/lamp/proc/escape_with(datum/act/op/A)
	after(5, "later", with = A)
	return TRUE

/obj/machinery/lamp/proc/escape_add(datum/act/op/A)
	queue.Add(A)
	queue += A
	return TRUE

/obj/machinery/lamp/proc/escape_after_snapshot(datum/act/op/A)
	after(5, "later", with = A.snapshot())
	return TRUE

/obj/machinery/lamp/proc/escape_allowed(datum/act/op/A)
	saved = A // ALLOW(handlers): the kernel hands this one back before the trigger ends
	return TRUE
