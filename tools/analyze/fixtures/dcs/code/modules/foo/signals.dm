/obj/thing/Initialize(mapload)
	. = ..()
	RegisterSignal(src, COMSIG_ATOM_ENTERED, PROC_REF(on_enter))
	UnregisterSignal(src, COMSIG_ATOM_ENTERED)
	RegisterSignals(src, list(COMSIG_A, COMSIG_B), PROC_REF(on_enter))
	SEND_SIGNAL(src, COMSIG_THING_POKED, 1)
	SEND_GLOBAL_SIGNAL(COMSIG_GLOB_X)
	AddComponent(/datum/component/thing)
	var/datum/component/thing/T = GetComponent(/datum/component/thing)
	AddElement(/datum/element/foo)
	RemoveElement(/datum/element/foo)
	// a comment mentioning RegisterSignal( and COMSIG_ANYTHING is ignored
	to_chat(usr, "a string mentioning SEND_SIGNAL( and COMSIG_X is ignored")
	x.my_RegisterSignal(1)
	/obj/AddComponent_not_a_call
	AddComponent (/datum/component/spaced)

/obj/thing/proc/on_enter()
	SIGNAL_HANDLER
	return
