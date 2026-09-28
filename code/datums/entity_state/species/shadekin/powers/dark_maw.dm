// Ported to the ability framework (doc/rewrite/rules.md §5). The 1-second
// channel is the time cost (pay_cost()); the trap only spawns and the energy
// only spends in the effect, together, once the channel finishes and every
// requirement still holds.

/datum/interaction/ability/self/shadekin_dark_maw
	id = ABILITY_ID_SHADEKIN_DARK_MAW
	name = "Dark maw"
	category = ABILITY_CAT_OFFENSE
	requires = list(
		REQ_CONSCIOUS,
		REQ_ON(PRED_ACTOR, /mob/living/proc/dq_pred_not_vr, "the VR systems cannot comprehend this power"),
		REQ_ON(PRED_ACTOR, /mob/living/proc/dq_pred_shadekin, "you aren't shadekin"),
		REQ_ON_TURF,
		REQ_ON(PRED_ACTOR, /mob/living/proc/dq_pred_dark_maw_dark_enough, "there is too much light here for your trap to last"),
		REQ_RESOURCE(/mob/living/proc/dq_dark_maw_afford),
	)
	effect = /mob/living/proc/dq_do_dark_maw

/datum/interaction/ability/self/shadekin_dark_maw/pay_cost(mob/actor, atom/target, obj/item/held)
	var/started = om_task_start(/datum/om/task/timed/interaction_cost, actor, null, duration = 1 SECOND, acted_on = target, held = held)
	return istext(started) ? FALSE : USE_TOOL_PENDING

/mob/living/proc/dq_pred_dark_maw_dark_enough(mob/living/actor, atom/target, obj/item/held)
	var/turf/T = get_turf(actor)
	return (T.get_lumcount() < 0.5) || "there is too much light here for your trap to last"

/mob/living/proc/dq_dark_maw_afford(mob/living/actor, atom/target, obj/item/held)
	var/datum/shadekin/SK = actor.get_shadekin_state()
	if(!SK)
		return "you aren't shadekin"
	return (SK.shadekin_get_energy() >= 20) || "not enough energy for that ability"

/mob/living/proc/dq_do_dark_maw(mob/living/actor, obj/item/held, datum/interaction/ability/interaction)
	var/datum/shadekin/SK = actor.get_shadekin_state()
	if(!SK)
		return FALSE
	if(SK.in_phase)
		new /obj/effect/abstract/dark_maw(actor.loc, actor, TRUE)
	else
		new /obj/effect/abstract/dark_maw(actor.loc, actor)
	SK.shadekin_adjust_energy(-20)
	return TRUE

/datum/interaction/ability/self/shadekin_dark_maw/clear
	id = "shadekin_clear_dark_maws"
	name = "Dispel dark maws"
	category = ABILITY_CAT_OFFENSE
	requires = list(REQ_ON(PRED_ACTOR, /mob/living/proc/dq_pred_shadekin, "you aren't shadekin"))
	effect = /mob/living/proc/dq_do_clear_dark_maws

/mob/living/proc/dq_do_clear_dark_maws(mob/living/actor, obj/item/held, datum/interaction/ability/interaction)
	var/datum/shadekin/SK = actor.get_shadekin_state()
	if(!SK)
		return FALSE
	for(var/obj/effect/abstract/dark_maw/dm as anything in SK.active_dark_maws)
		dm.dispel()
	return TRUE

/obj/effect/abstract/dark_maw
	var/owner_handle
	var/target_handle
	var/has_signal = FALSE
	icon = 'icons/obj/Shadekin_powers.dmi'
	icon_state = "dark_maw_waiting"

/obj/effect/abstract/dark_maw/Initialize(mapload, mob/user, trigger_now = FALSE)
	. = ..()
	if(!isturf(loc))
		return INITIALIZE_HINT_QDEL
	var/datum/shadekin/SK
	if(user && isliving(user))
		owner_handle = om_handle(user)
		if(owner().vore_selected)
			target_handle = om_handle(owner().vore_selected)
		om_hook(owner(), /datum/om/event/qdeleting, src, PROC_REF(drop_everything_and_delete))
		has_signal = TRUE
		SK = owner().get_shadekin_state()

	var/turf/T = loc
	if(T.get_lumcount() >= 0.5)
		visible_message(span_notice("A set of shadowy lines flickers away in the light."))
		icon_state = "dark_maw_used"
		return INITIALIZE_HINT_QDEL

	var/mob/living/target_user = null
	for(var/mob/living/L in turf_contents_of_type(T, /mob/living))
		if(L != owner() && !L.is_incorporeal())
			target_user = L
			break

	if(istype(target_user))
		triggered_by(target_user, 1)
		// to trigger rebuild
	else if(trigger_now)
		icon_state = "dark_maw_used"
		flick("dark_maw_tr", src)
		visible_message(span_warning("A set of crystals suddenly springs from the ground and shadowy tendrils wrap around nothing before vanishing."))
		expire(3 SECONDS)
	else
		if(SK)
			LAZYADD(SK.active_dark_maws, src)
		flick("dark_maw", src)
		PERIODIC_START(src, PERIODIC_SLOW)

///Called when we get a signal that our owner is being qdel'd
/obj/effect/abstract/dark_maw/proc/drop_everything_and_delete(datum/source, datum/om/event/qdeleting/event)
	EVENT_HANDLER
	qdel(src)

// leaves its shadekin's maw list (the shadekin datum lives on the owner, not in a var).
REF_BACK_VIA(/obj/effect/abstract/dark_maw, list("owner_handle.shadekin" = "active_dark_maws"))

/obj/effect/abstract/dark_maw/Crossed(O)
	. = ..()
	if(!isliving(O))
		return
	if(icon_state != "dark_maw_waiting")
		return
	var/mob/living/L = O
	if(!L.is_incorporeal() && (!owner() || L != owner()))
		triggered_by(L)

/obj/effect/abstract/dark_maw/periodic_step()
	var/turf/T = get_turf(src)
	if(!istype(T) || T.get_lumcount() >= 0.5)
		dispel()

/obj/effect/abstract/dark_maw/proc/dispel()
	if(icon_state == "dark_maw_waiting")
		visible_message(span_notice("A set of shadowy lines flickers away in the light."))
	else
		visible_message(span_notice("The crystals and shadowy tendrils dissipate with the light shone on it."))
	icon_state = "dark_maw_used"
	qdel(src)

/obj/effect/abstract/dark_maw/proc/triggered_by(mob/living/L, triggered_instantly = 0)
	PERIODIC_STOP(src)
	icon_state = "dark_maw_used"
	flick("dark_maw_tr", src)
	L.status_adjust(EFFECT_STUNNED, 4)
	visible_message(span_warning("A set of crystals spring out of the ground and shadowy tendrils start wrapping around [L]."))
	if(owner() && !triggered_instantly)
		to_chat(owner(), span_warning("A dark maw you deployed has triggered!"))
	om_after(src, 1 SECOND, PROC_REF(do_trigger), L)

/obj/effect/abstract/dark_maw/proc/do_trigger(mob/living/L)
	var/will_vore = 1

	if(!(target() in owner()) || !can_phase_vore(owner(), L, TRUE))
		will_vore = 0

	if(!src || src.gc_destroyed)
		//We got deleted probably, do nothing more
		return

	if(L.loc != get_turf(src))
		visible_message(span_notice("The shadowy tendrils fail to catch anything and dissipate."))
		qdel(src)
		return

	if(will_vore)
		visible_message(span_warning("The shadowy tendrils grab around [L] and drag them into the floor, leaving nothing behind."))
		target().nom_atom(L)
		qdel(src)
		return

	var/obj/effect/energy_net/dark/net = new /obj/effect/energy_net/dark(get_turf(src))
	if(net.buckle_mob(L))
		visible_message(span_warning("The shadowy tendrils wrap around [L] and traps them in a net of dark energy."))
	else
		visible_message(span_notice("The shadowy tendrils wrap around [L] and then dissipate, leaving them in place."))
	qdel(src)

/obj/effect/energy_net/dark
	name = "dark net"
	desc = "It's a net made of dark energy."
	icon = 'icons/obj/Shadekin_powers.dmi'
	icon_state = "dark_net"

	escape_time = 30 SECONDS

/obj/effect/energy_net/dark/user_unbuckle_mob(mob/living/buckled_mob, mob/user)
	if(isliving(user))
		var/mob/living/unbuckler = user
		var/datum/shadekin/SK = unbuckler.get_shadekin_state()
		if(SK)
			visible_message(span_danger("[user] dissipates \the [src] with a touch!"))
			unbuckle_mob(buckled_mob)
			return
	. = ..()

/obj/effect/energy_net/dark/periodic_step()
	. = ..()
	var/turf/T = get_turf(src)
	if(!istype(T) || T.get_lumcount() >= 0.6)
		visible_message(span_notice("The tangle of dark tendrils fades away in the light."))
		qdel(src)

/// LC-refs: the shadekin who opened the maw -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/effect/abstract/dark_maw/proc/owner() as /mob/living
	return om_resolve(owner_handle)

/// LC-refs: the belly the maw feeds -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/effect/abstract/dark_maw/proc/target() as /obj/belly
	return om_resolve(target_handle)
