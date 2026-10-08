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

/datum/om/check/holding_tool
	depends_on = CHANGE_MOB_HANDS

/datum/om/check/holding_tool/why_not(datum/actor, datum/target)
	var/mob/M = actor
	if(!istype(M))
		return "has no hands"
	var/obj/item/I = M.get_active_hand()
	if(!istype(I) || !I.has_tool_quality(param(actor)))
		return "needs the right tool"

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

/datum/om/check/target_exists
/datum/om/check/target_exists/why_not(datum/actor, datum/target)
	if(!target || QDELETED(target))
		return "it's gone"

/datum/om/check/var_below
/datum/om/check/var_below/why_not(datum/actor, datum/target)
	var/list/A = param(actor)
	var/datum/S = subject(actor, target)
	if(!islist(A) || !S || !(S.vars[A[1]] < A[2]))
		return "too high"

// ---------------------------------------------------------------- prompt re-checks (om_prompt)

/// The target is somewhere on the actor (held, worn, or inside something carried).
/datum/om/check/carried
	depends_on = CHANGE_MOB_HANDS | CHANGE_ITEM_LOC

/datum/om/check/carried/why_not(datum/actor, datum/target)
	var/atom/movable/T = target
	if(!istype(T))
		return "not carrying it"
	for(var/atom/holder = T.loc; holder; holder = holder.loc)
		if(holder == actor)
			return null
	return "not carrying it"

/// The target is in one of the actor's hands.
/datum/om/check/in_hands
	depends_on = CHANGE_MOB_HANDS

/datum/om/check/in_hands/why_not(datum/actor, datum/target)
	var/mob/M = actor
	if(!istype(M) || !target || (M.get_active_hand() != target && M.get_inactive_hand() != target))
		return "not holding it"

/// The actor is not incapacitated (arg: INCAPACITATION_* flags).
/datum/om/check/not_incapacitated
	depends_on = CHANGE_MOB_STAT | CHANGE_MOB_STATUS
	arg = INCAPACITATION_DEFAULT

/datum/om/check/not_incapacitated/why_not(datum/actor, datum/target)
	var/mob/M = actor
	if(!istype(M) || M.incapacitated(param(actor)))
		return "not able to"

/// The actor can still work the target through a tgui state (arg: the state's name in
/// GLOB.tgui_<name>_state, default "default": adjacency, silicon access, consciousness).
/datum/om/check/ui_usable
	depends_on = CHANGE_MOB_LOC | CHANGE_ITEM_LOC | CHANGE_MOB_STAT
	arg = "default"

/datum/om/check/ui_usable/why_not(datum/actor, datum/target)
	var/mob/M = actor
	var/datum/tgui_state/S = GLOB.vars["tgui_[param(actor)]_state"]
	if(!istype(M) || !target || !istype(S) || S.can_use_topic(target, M) < STATUS_INTERACTIVE)
		return "can't use it"

/// The actor's player holds admin rights (arg: R_* flags; 0 = any admin rank).
/datum/om/check/admin_rights
	arg = 0

/datum/om/check/admin_rights/why_not(datum/actor, datum/target)
	var/mob/M = actor
	var/client/C = istype(M) ? M.client : null
	if(!admin_can(C, 0) || !check_rights_for(C, param(actor)))
		return "no admin rights"

/// The actor is directly inside the target (a tunnel, a closet, a vehicle).
/datum/om/check/inside_target
	depends_on = CHANGE_MOB_LOC

/datum/om/check/inside_target/why_not(datum/actor, datum/target)
	var/atom/movable/A = actor
	if(!istype(A) || !target || A.loc != target)
		return "not inside it"
