// Object-model core: the standard check library (doc/rewrite/object_model_core.md, "Library").
// Parameters come from CHECK(path, arg) / list(path = arg); FROM_VAR args read the actor.

/datum/om/check/adjacent
	depends_on = CHANGE_MOB_LOC | CHANGE_ITEM_LOC

/datum/om/check/adjacent/why_not(datum/actor, datum/target)
	var/atom/A = actor
	var/atom/T = target
	if(!istype(A) || !istype(T) || !A.Adjacent(T))
		return "too far away"

/datum/om/check/in_range
	depends_on = CHANGE_MOB_LOC | CHANGE_ITEM_LOC
	arg = 1

/datum/om/check/in_range/why_not(datum/actor, datum/target)
	var/atom/A = actor
	var/atom/T = target
	if(!istype(A) || !istype(T))
		return "too far away"
	var/turf/at = get_turf(A)
	var/turf/tt = get_turf(T)
	if(!at || !tt || at.z != tt.z || get_dist(at, tt) > param(actor))
		return "too far away"

/datum/om/check/can_see
	depends_on = CHANGE_MOB_LOC
	arg = 7

/datum/om/check/can_see/why_not(datum/actor, datum/target)
	var/atom/A = actor
	var/atom/T = target
	if(!istype(A) || !istype(T) || !can_see(A, T, param(actor)))
		return "can't see it"

/datum/om/check/can_reach
	depends_on = CHANGE_MOB_LOC | CHANGE_MOB_HANDS

/datum/om/check/can_reach/why_not(datum/actor, datum/target)
	var/atom/A = actor
	var/atom/movable/T = target
	if(!istype(A) || !istype(T))
		return "can't reach it"
	for(var/atom/loc = T.loc; loc; loc = loc.loc)
		if(loc == A)
			return null
	if(!A.Adjacent(T))
		return "can't reach it"

/datum/om/check/holding
	depends_on = CHANGE_MOB_HANDS

/datum/om/check/holding/why_not(datum/actor, datum/target)
	var/mob/M = actor
	if(!istype(M))
		return "has no hands"
	var/path = param(actor)
	if(istype(M.get_active_hand(), path) || istype(M.get_inactive_hand(), path))
		return null
	return "not holding the right thing"

/datum/om/check/holding_tool
	depends_on = CHANGE_MOB_HANDS

/datum/om/check/holding_tool/why_not(datum/actor, datum/target)
	var/mob/M = actor
	if(!istype(M))
		return "has no hands"
	var/obj/item/I = M.get_active_hand()
	if(!istype(I) || !I.has_tool_quality(param(actor)))
		return "needs the right tool"

/datum/om/check/hands_free
	depends_on = CHANGE_MOB_HANDS

/datum/om/check/hands_free/why_not(datum/actor, datum/target)
	var/mob/M = actor
	if(!istype(M) || M.get_active_hand())
		return "hands are full"

/datum/om/check/wearing
	depends_on = CHANGE_MOB_EQUIPMENT

/datum/om/check/wearing/why_not(datum/actor, datum/target)
	var/mob/M = actor
	if(!istype(M))
		return "can't wear things"
	var/path = param(actor)
	for(var/obj/item/I as anything in M.get_equipped_items())
		if(istype(I, path))
			return null
	return "not wearing the right thing"

/datum/om/check/has_client
	depends_on = CHANGE_MOB_CLIENT

/datum/om/check/has_client/why_not(datum/actor, datum/target)
	var/mob/M = actor
	if(!istype(M) || !M.client)
		return "nobody is playing it"

/datum/om/check/stat_at_most
	depends_on = CHANGE_MOB_STAT
	arg = CONSCIOUS

/datum/om/check/stat_at_most/why_not(datum/actor, datum/target)
	var/mob/M = actor
	if(!istype(M) || M.stat > param(actor))
		return "not able to"

/datum/om/check/conscious
	depends_on = CHANGE_MOB_STAT

/datum/om/check/conscious/why_not(datum/actor, datum/target)
	var/mob/M = actor
	if(!istype(M) || M.stat != CONSCIOUS)
		return "not conscious"

/datum/om/check/alive
	depends_on = CHANGE_MOB_STAT

/datum/om/check/alive/why_not(datum/actor, datum/target)
	var/mob/M = subject(actor, target)
	if(!istype(M) || M.stat == DEAD)
		return "not alive"

/datum/om/check/not_restrained
	depends_on = CHANGE_MOB_STATUS

/datum/om/check/not_restrained/why_not(datum/actor, datum/target)
	var/mob/M = actor
	if(!istype(M) || M.restrained())
		return "restrained"

/datum/om/check/is_type
/datum/om/check/is_type/why_not(datum/actor, datum/target)
	if(!istype(subject(actor, target), param(actor)))
		return "wrong kind of thing"

/datum/om/check/target_exists
/datum/om/check/target_exists/why_not(datum/actor, datum/target)
	if(!target || QDELETED(target))
		return "it's gone"

/datum/om/check/has_effect
	depends_on = CHANGE_EFFECTS

/datum/om/check/has_effect/why_not(datum/actor, datum/target)
	if(!om_has(subject(actor, target), param(actor)))
		return "not [param(actor)]"

/datum/om/check/lacks_effect
	depends_on = CHANGE_EFFECTS

/datum/om/check/lacks_effect/why_not(datum/actor, datum/target)
	if(om_has(subject(actor, target), param(actor)))
		return "[param(actor)]"

/// arg = list(kind, id)
/datum/om/check/has_grant
	depends_on = CHANGE_EFFECTS

/datum/om/check/has_grant/why_not(datum/actor, datum/target)
	var/list/A = param(actor)
	if(!islist(A) || !om_has_grant(subject(actor, target), A[1], A[2]))
		return "not allowed"

/// arg = list(var name, value). Declare depends_on in a subtype for wake-ups.
/datum/om/check/var_above
/datum/om/check/var_above/why_not(datum/actor, datum/target)
	var/list/A = param(actor)
	var/datum/S = subject(actor, target)
	if(!islist(A) || !S || !(S.vars[A[1]] > A[2]))
		return "too low"

/datum/om/check/var_below
/datum/om/check/var_below/why_not(datum/actor, datum/target)
	var/list/A = param(actor)
	var/datum/S = subject(actor, target)
	if(!islist(A) || !S || !(S.vars[A[1]] < A[2]))
		return "too high"

/// arg = var name.
/datum/om/check/var_true
/datum/om/check/var_true/why_not(datum/actor, datum/target)
	var/datum/S = subject(actor, target)
	if(!S || !S.vars[param(actor)])
		return "not ready"

/// arg = derived name.
/datum/om/check/derived_true
/datum/om/check/derived_true/why_not(datum/actor, datum/target)
	var/datum/S = subject(actor, target)
	if(!S || !om_derived(S, param(actor)))
		return "not ready"

/datum/om/check/powered
	depends_on = CHANGE_MACHINE_POWER

/datum/om/check/powered/why_not(datum/actor, datum/target)
	var/obj/machinery/M = subject(actor, target)
	if(!istype(M) || (M.stat & NOPOWER))
		return "no power"

/datum/om/check/holder_powered
	depends_on = CHANGE_ITEM_LOC

/datum/om/check/holder_powered/why_not(datum/actor, datum/target)
	var/atom/movable/S = subject(actor, target)
	var/obj/machinery/M = istype(S) ? S.loc : null
	if(!istype(M) || (M.stat & NOPOWER))
		return "no power"

/datum/om/check/not_broken
	depends_on = CHANGE_MACHINE_BROKEN

/datum/om/check/not_broken/why_not(datum/actor, datum/target)
	var/obj/machinery/M = subject(actor, target)
	if(istype(M) && (M.stat & BROKEN))
		return "broken"

/datum/om/check/panel_open
	depends_on = CHANGE_MACHINE_PANEL

/datum/om/check/panel_open/why_not(datum/actor, datum/target)
	var/obj/machinery/M = subject(actor, target)
	if(!istype(M) || !M.panel_open)
		return "the panel is closed"

/datum/om/check/panel_closed
	depends_on = CHANGE_MACHINE_PANEL

/datum/om/check/panel_closed/why_not(datum/actor, datum/target)
	var/obj/machinery/M = subject(actor, target)
	if(istype(M) && M.panel_open)
		return "the panel is open"

/datum/om/check/anchored
	depends_on = CHANGE_MACHINE_ANCHORED

/datum/om/check/anchored/why_not(datum/actor, datum/target)
	var/atom/movable/S = subject(actor, target)
	if(!istype(S) || !S.anchored)
		return "not secured"

/datum/om/check/unanchored
	depends_on = CHANGE_MACHINE_ANCHORED

/datum/om/check/unanchored/why_not(datum/actor, datum/target)
	var/atom/movable/S = subject(actor, target)
	if(istype(S) && S.anchored)
		return "secured in place"

/datum/om/check/has_access
/datum/om/check/has_access/why_not(datum/actor, datum/target)
	var/obj/O = target
	var/mob/M = actor
	if(!istype(O) || !istype(M) || !O.allowed(M))
		return "access denied"

/// arg = slot id in the holder's ledger.
/datum/om/check/in_slot
	depends_on = CHANGE_ITEM_LOC

/datum/om/check/in_slot/why_not(datum/actor, datum/target)
	var/atom/movable/S = subject(actor, target)
	if(!istype(S) || !S.loc)
		return "not there"
	var/datum/ledger/L = dq_ledger_peek(S.loc)
	var/list/entry = L?.entries[S]
	if(!entry || entry[LEDGER_E_SLOT] != param(actor))
		return "not there"

/// arg = oxygen partial pressure threshold in kPa. Passes when the subject's turf is below it.
/datum/om/check/turf_o2_low
	arg = 16

/datum/om/check/turf_o2_low/why_not(datum/actor, datum/target)
	var/atom/S = subject(actor, target)
	var/turf/T = istype(S) ? get_turf(S) : null
	var/datum/gas_mixture/air = T?.return_air()
	if(!air)
		return null
	var/total = air.total_moles()
	if(total <= 0)
		return null
	var/partial = air.return_pressure() * (air.get_moles(/datum/gas/oxygen) || 0) / total
	if(partial >= param(actor))
		return "there is enough oxygen"

/// arg = z level.
/datum/om/check/on_z
	depends_on = CHANGE_MOB_LOC | CHANGE_ITEM_LOC

/datum/om/check/on_z/why_not(datum/actor, datum/target)
	var/atom/S = subject(actor, target)
	var/turf/T = istype(S) ? get_turf(S) : null
	if(!T || T.z != param(actor))
		return "somewhere else"

/datum/om/check/same_z
	depends_on = CHANGE_MOB_LOC | CHANGE_ITEM_LOC

/datum/om/check/same_z/why_not(datum/actor, datum/target)
	var/atom/AA = actor
	var/atom/TT = target
	if(!istype(AA) || !istype(TT))
		return "somewhere else"
	var/turf/A = get_turf(AA)
	var/turf/T = get_turf(TT)
	if(!A || !T || A.z != T.z)
		return "somewhere else"

/// arg = container type.
/datum/om/check/in_container
	depends_on = CHANGE_ITEM_LOC | CHANGE_MOB_LOC

/datum/om/check/in_container/why_not(datum/actor, datum/target)
	var/atom/movable/S = subject(actor, target)
	if(!istype(S) || !istype(S.loc, param(actor)))
		return "not inside it"

/datum/om/check/is_living
/datum/om/check/is_living/why_not(datum/actor, datum/target)
	if(!isliving(subject(actor, target)))
		return "not alive"
