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
//
// setup(PROC_REF(x), mapload = TRUE) is the hook that is an Initialize()'s tail: x(mapload) gets what Initialize(mapload) got and returns an
// init hint, INITIALIZE_HINT_NORMAL (or null) or INITIALIZE_HINT_QDEL. QDEL deletes the instance exactly as the same return from Initialize()
// does (InitAtom() takes it from there: the same spent() and logging), and the hooks after it, after_init() and the rest do not run. Any other
// hint is a stack_trace() and is ignored. It runs at the same point as every setup() hook, in declaration order, and is not available with
// with_params = TRUE (that phase cannot return a hint). Only a hook declared with mapload = TRUE has its return read.
//
//	CAPABILITIES(/obj/effect/overmap/visitable/sector/temporary)
//		setup(PROC_REF(claim_zlevel), mapload = TRUE)   // x(mapload): return INITIALIZE_HINT_QDEL when it cannot stay

/// with_params opts into the constructor-completion phase: the complete Initialize
/// chain has returned, but keep=FALSE arguments have not been dropped yet. Ordinary
/// setup on an opted-in holder runs after parameter drop; other holders retain
/// their existing setup-before-drop ordering. Rejected constructors run neither phase.
/// mapload = TRUE: the hook is x(mapload) and returns an init hint (see the head of this file).
/proc/setup(handler, with_params = FALSE, mapload = FALSE)
	if(!istext(handler))
		declare_report("setup(): the hook is PROC_REF(x), got [handler]")
		return null
	if(mapload && with_params)
		declare_report("setup([handler]): mapload = TRUE cannot combine with with_params = TRUE; the constructor-completion phase cannot return an init hint")
		return null
	return entry_make(ENTRY_SETUP, "setup:[handler]", list("handler" = handler, "with_params" = !!with_params, "mapload" = !!mapload))

/// name_prefix(prefix): the instance's name starts with `prefix` (a text, or a PROC_REF answering one) at the setup phase.
/proc/name_prefix(prefix)
	return entry_make(ENTRY_SETUP, "setup:name_prefix", list("prefix" = prefix))

/// instance -> TRUE while its setup hooks wait for Initialize() to return. A real global: atoms initialize while the globals are still being made.
GLOBAL_REAL_VAR(list/setup_pending)

/// At init (lifeform_init): the instance has setup hooks to run when its Initialize() returns.
/proc/setup_note(datum/holder, datum/lifeform_plan/P)
	if(!setup_pending)
		setup_pending = list()
	setup_pending[holder] = P.setup_with_params ? SETUP_PENDING_WITH_PARAMS : SETUP_PENDING_REGULAR

/// InitAtom(), when Initialize() returned: the hooks, in order. Returns INITIALIZE_HINT_QDEL when a mapload = TRUE hook asked for the instance's
/// deletion (the rest do not run; InitAtom() applies it as it would an Initialize() return), else INITIALIZE_HINT_NORMAL.
/proc/setup_run(datum/holder, with_params = FALSE, mapload = FALSE)
	if(QDELETED(holder))
		setup_pending -= holder
		return INITIALIZE_HINT_NORMAL
	if(with_params)
		if(setup_pending?[holder] != SETUP_PENDING_WITH_PARAMS)
			return INITIALIZE_HINT_NORMAL
		setup_pending[holder] = SETUP_PENDING_REGULAR // consume before calling a reentrant handler
	else
		setup_pending -= holder
	var/datum/lifeform_plan/P = lifeform_plan_of(holder)
	for(var/datum/centry/C as anything in P.setups)
		var/datum/entry/E = C.item
		if(!!E.args["with_params"] != !!with_params)
			continue
		var/handler = E.args["handler"]
		if(handler)
			if(E.args["mapload"])
				var/hint = call(holder, handler)(mapload)
				if(hint == INITIALIZE_HINT_QDEL)
					log_world("setup([handler]) on [holder.type] returned INITIALIZE_HINT_QDEL (mapload=[mapload ? 1 : 0]): the instance is discarded")
					return INITIALIZE_HINT_QDEL
				if(!isnull(hint) && hint != INITIALIZE_HINT_NORMAL)
					stack_trace("setup([handler]) on [holder.type] returned init hint [hint]; only INITIALIZE_HINT_NORMAL and INITIALIZE_HINT_QDEL are supported there")
			else
				call(holder, handler)()
		else if(!isnull(E.args["prefix"]) && isatom(holder))
			var/atom/A = holder
			var/prefix = E.args["prefix"]
			if(istext(prefix) && hascall(holder, prefix))
				prefix = call(holder, prefix)()
			A.name = "[prefix] [A.name]"
		if(QDELETED(holder))
			setup_pending -= holder
			return INITIALIZE_HINT_NORMAL
	return INITIALIZE_HINT_NORMAL
