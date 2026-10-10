// keeps_if(PROC_REF(cond), warn =): an atom kept only when its init finds `cond` true; otherwise its Initialize() answers INITIALIZE_HINT_QDEL
// (doc/rewrite/final_api.html section 6 "Lifecycle forms"). It takes the Initialize() override that only did
//
//	/obj/structure/stairs/top/Initialize(mapload)
//		. = ..()
//		if(!GetBelow(src))
//			WARNING("Stair created without level below: ([loc.x], [loc.y], [loc.z])")
//			return INITIALIZE_HINT_QDEL
//
// as
//
//	CAPABILITIES(/obj/structure/stairs/top)
//		keeps_if(PROC_REF(has_level_below), warn = "Stair created without level below")
//
// `cond` is a holder proc (a condition: it reads, never writes) asked once, at the start of the lifeform init (the root of the Initialize()
// chain, after the capabilities' init), where the old check ran right after `. = ..()`. `warn =` logs a WARNING() with the place when the atom
// is discarded (a map error). The discard is the atoms system's: InitAtom() turns the normal hint into INITIALIZE_HINT_QDEL when Initialize()
// returns, so a subtype's code after `. = ..()` still runs, as it did when the parent returned the hint. Only an atom has an init hint; a plain
// datum that declares it is reported.

/proc/keeps_if(cond, warn = null)
	if(!istext(cond))
		declare_report("keeps_if(): the condition is PROC_REF(x), got [cond]")
		return null
	return entry_make(ENTRY_KEEPS_IF, "keeps_if", list("cond" = cond, "warn" = warn))

/// instance -> TRUE when its keeps_if() failed: InitAtom() discards it when Initialize() returns. A real global: atoms initialize while the
/// globals are still being made.
GLOBAL_REAL_VAR(list/init_discard_pending)

/// At init: the first failing keeps_if() marks the atom for discard.
/proc/keeps_if_init(datum/holder, datum/lifeform_plan/P)
	if(!isatom(holder))
		stack_trace("keeps_if() on [holder.type]: only an atom has an init hint")
		return
	for(var/datum/centry/C as anything in P.keeps_if)
		var/datum/entry/E = C.item
		if(call(holder, E.args["cond"])())
			continue
		var/warn = E.args["warn"]
		if(warn)
			var/atom/A = holder
			var/turf/T = get_turf(A)
			WARNING("[warn]: ([T?.x], [T?.y], [T?.z])")
		if(!init_discard_pending)
			init_discard_pending = list()
		init_discard_pending[holder] = TRUE
		return

/// InitAtom()'s question when Initialize() returned: did a keeps_if() fail? Clears the mark.
/proc/keeps_if_discarded(atom/A)
	if(!init_discard_pending?[A])
		return FALSE
	init_discard_pending -= A
	return TRUE
