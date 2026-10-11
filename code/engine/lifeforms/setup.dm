// setup(PROC_REF(x)) and name_prefix(prefix): the type's own setup as named, ordered hooks (doc/rewrite/final_api.html section 6, "The init phase
// contract", phase 3). They replace an Initialize() override's code after `..()`:
//
//	CAPABILITIES(/obj/item/clothing/mask/smokable/pipe)
//		name_prefix("empty")                       // was: name = "empty [initial(name)]"
//	CAPABILITIES(/obj/machinery/teleport/hub)
//		setup(PROC_REF(draw_wiring))               // was: underlays += ... after ..()
//
// When they run: when the instance's Initialize() chain has returned (InitAtom()), before after_init(): every declared child exists, every
// capability is initialized, and the code each type still runs after `..()` has run. In declaration order, ancestors first; a subtype that
// declares setup() with the same proc does not run it twice (the entry is keyed by its proc). x() takes no arguments and returns nothing.
// A discarded instance (keeps_if()) runs none.

/proc/setup(handler)
	if(!istext(handler))
		declare_report("setup(): the hook is PROC_REF(x), got [handler]")
		return null
	return entry_make(ENTRY_SETUP, "setup:[handler]", list("handler" = handler))

/// name_prefix(prefix): the instance's name starts with `prefix` (a text, or a PROC_REF answering one) at the setup phase.
/proc/name_prefix(prefix)
	return entry_make(ENTRY_SETUP, "setup:name_prefix", list("prefix" = prefix))

/// instance -> TRUE while its setup hooks wait for Initialize() to return. A real global: atoms initialize while the globals are still being made.
GLOBAL_REAL_VAR(list/setup_pending)

/// At init (lifeform_init): the instance has setup hooks to run when its Initialize() returns.
/proc/setup_note(datum/holder)
	if(!setup_pending)
		setup_pending = list()
	setup_pending[holder] = TRUE

/// InitAtom(), when Initialize() returned: the hooks, in order.
/proc/setup_run(datum/holder)
	setup_pending -= holder
	if(QDELETED(holder))
		return
	var/datum/lifeform_plan/P = lifeform_plan_of(holder)
	for(var/datum/centry/C as anything in P.setups)
		var/datum/entry/E = C.item
		var/handler = E.args["handler"]
		if(handler)
			call(holder, handler)()
		else if(!isnull(E.args["prefix"]) && isatom(holder))
			var/atom/A = holder
			var/prefix = E.args["prefix"]
			if(istext(prefix) && hascall(holder, prefix))
				prefix = call(holder, prefix)()
			var/prefixed_name = "[prefix] [A.name]"
			if(hascall(A, "__setter_name"))
				call(A, "set_name")(prefixed_name)
			else
				A.name = prefixed_name
		if(QDELETED(holder))
			return
