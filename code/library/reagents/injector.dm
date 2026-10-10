// injector(...) (doc/rewrite/final_api.html, section 11; section 16.5): a hypospray, an autoinjector: it puts one transfer of what it holds into a person's blood
// by a click, through armour (the nozzle finds a port). On top of reagent_container(). What it does to the one injected (the transfer, the sound, the log, a
// spent autoinjector) is the holder type's own effect: it extends the op, `extend("injector.inject", then(PROC_REF(injected)))`.
//
//   CAPABILITIES(/obj/item/reagent_containers/hypospray,
//       reagent_container(volume = nameof(volume), needle = TRUE, settable = FALSE, ...),
//       injector(slow = nameof(prototype)),
//       extend("injector.inject", then(PROC_REF(injected))),
//       extend("injector.inject_slowly", then(PROC_REF(injected))))
//
// Ops (all "injector.<name>"):
//   inject         a click on a person (a human): at once, unless it is "slow" (below)
//   inject_slowly  the same after three seconds, when it goes into somebody else and the injector is slow (`slow` names a holder var that says it, the
//                  prototype's) or that person is awake, in combat mode and resists; the one who begins is seen to
//   unload         (`vial` names the holder var of the vial slot) an empty hand on the injector, held in the other hand: the vial comes out
//
// Requirements: something in it, nothing a belly made for somebody who will not take it, the limb aimed at is there. The thick hide of some species
// is a roll made when the needle goes in (a first effect of both ops): it turns the injection away.

CAPABILITY_TYPE(injector, CAP_INJECTOR, /datum/capability/lib/injector, key = NONE, slow = null, vial = null, resist_wait = 30)

MSG_DEF_SELF(injector/empty, "It is empty.")
MSG_DEF_SELF(injector/limb_missing, "They are missing that limb!")
MSG_DEF_SELF(injector/from_belly, "That contains something produced from a belly, and it won't be taken!")
MSG_DEF(injector/begin, "You begin to inject %T% with %I%.", "%U% is trying to inject %T% with %I%!")
MSG_DEF(injector/begin_resisted, "%T% resists your attempt to inject them with %I%.", "%U% is trying to inject %T% with %I%!")

/datum/capability/lib/injector/entries()
	return list(
		op("inject", at_target(/mob/living/carbon/human), when(cond_not(CAP_PROC(goes_slowly))), priority(OP_PRIORITY_PART), label("Inject"),
			needs(req_reagents(1, because = MSG(injector/empty)), req(CAP_PROC(belly_free)),
				req(CAP_PROC(limb_there))),
			then(CAP_PROC(skin_holds_up))),
		op("inject_slowly", at_target(/mob/living/carbon/human), when(CAP_PROC(goes_slowly)), priority(OP_PRIORITY_PART), label("Inject"),
			begins(CAP_PROC(begin_message)), wait(CAP_PROC(slow_wait)),
			needs(req_reagents(1, because = MSG(injector/empty)), req(CAP_PROC(belly_free)),
				req(CAP_PROC(limb_there))),
			then(CAP_PROC(skin_holds_up))),
		vial ? op("unload", hand(), when(CAP_PROC(unloadable)), priority(OP_PRIORITY_NORMAL + 5), label("Remove the vial")) : null)

/// Is the injector slow: a var of the holder says so.
/datum/capability/lib/injector/proc/is_slow(atom/holder)
	return !isnull(slow) && !!holder.vars[slow]

/// Somebody else is injected after a wait: always with a slow injector, and with any other when the one injected is awake, in combat mode and resists.
/datum/capability/lib/injector/proc/goes_slowly(datum/act/op/A)
	var/mob/living/carbon/human/target = A.target
	if(isnull(target) || target == A.actor)
		return FALSE
	if(is_slow(A.holder))
		return TRUE
	return !target.stat && target.combat_mode

/datum/capability/lib/injector/proc/slow_wait(datum/act/op/A)
	return resist_wait

/datum/capability/lib/injector/proc/begin_message(datum/act/op/A)
	return is_slow(A.holder) ? MSG(injector/begin) : MSG(injector/begin_resisted)

/datum/capability/lib/injector/proc/belly_free(datum/act/op/A)
	var/mob/living/target = A.target
	return (target.consume_liquid_belly || !reagents_from_belly(A.holder)) ? null : /datum/msg/injector/from_belly

/// The limb the one who injects aims at is on the person.
/datum/capability/lib/injector/proc/limb_there(datum/act/op/A)
	var/mob/living/carbon/human/target = A.target
	var/mob/user = A.actor
	return (!user?.zone_sel || !!target.get_organ(user.zone_sel.selecting)) ? null : /datum/msg/injector/limb_missing

/// The roll of a thick hide: TRUE (the injection goes on) unless it turns the needle away.
/datum/capability/lib/injector/proc/skin_holds_up(datum/act/op/A)
	var/mob/living/carbon/human/target = A.target
	var/mob/user = A.actor
	if(!user?.zone_sel)
		return OP_OK
	var/obj/item/organ/external/affected = target.get_organ(user.zone_sel.selecting)
	if(affected && target.thick_skin_holds(affected))
		to_chat(user, span_warning("Your needle fails to penetrate \the [affected]'s thick hide..."))
		return OP_REFUSED
	return OP_OK

/// The empty hand takes the vial out of an injector held in the other hand.
/datum/capability/lib/injector/proc/unloadable(datum/act/op/A)
	var/atom/holder = A.holder
	var/mob/user = A.actor
	return !isnull(vial) && !isnull(holder.vars[vial]) && user?.get_inactive_hand() == holder
