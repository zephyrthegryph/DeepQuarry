// The dark powers of a full shadekin (dark respite, dark tunneling, the dark maw and its dispelling). The channel is the op's wait(); the trap
// only deploys and the energy only spends in the effect, once the channel finishes and every requirement still holds.

MSG_DEF_SELF(shadekin_ability/too_bright_for_maw, "there is too much light here for your trap to last")
MSG_DEF_SELF(shadekin_ability/tunnel_made, "you have already made a tunnel to the Dark")

CAPABILITY_DEF(shadekin_dark, CAP_SHADEKIN_DARK, key = NONE)

/datum/capability/def/shadekin_dark/entries()
	return list(
		op("dark_respite", label("Dark respite"), menu(button = "Dark respite", bind = "ability_shadekin_dark_respite"),
			needs(req_conscious(),
				req(TYPE_PROC_REF(/mob/living, ability_not_in_vr), because = MSG(shadekin_ability/vr)),
				req(TYPE_PROC_REF(/mob/living, ability_is_shadekin), because = MSG(shadekin_ability/not_shadekin)),
				req(TYPE_PROC_REF(/mob/living, ability_not_shifted), because = MSG(shadekin_ability/phase_shifted)),
				req(TYPE_PROC_REF(/mob/living, ability_in_dark_respite_area), because = MSG(shadekin_ability/not_dark)),
				req(TYPE_PROC_REF(/mob/living, ability_respite_not_cooling_down), because = MSG(shadekin_ability/respite_cooldown)),
				req(TYPE_PROC_REF(/mob/living, ability_respite_endable), because = MSG(shadekin_ability/respite_forced))),
			then(TYPE_PROC_REF(/mob/living, ability_dark_respite))),
		op("dark_tunneling", label("Dark tunneling"), menu(button = "Dark tunneling", bind = "ability_shadekin_dark_tunneling"),
			needs(req_conscious(),
				req(TYPE_PROC_REF(/mob/living, ability_not_in_vr), because = MSG(shadekin_ability/vr)),
				req(TYPE_PROC_REF(/mob/living, ability_is_shadekin), because = MSG(shadekin_ability/not_shadekin)),
				req(TYPE_PROC_REF(/mob/living, ability_not_shifted), because = MSG(shadekin_ability/phase_shifted)),
				req(TYPE_PROC_REF(/mob/living, ability_no_dark_tunnel_yet), because = MSG(shadekin_ability/tunnel_made)),
				req(TYPE_PROC_REF(/mob/living, ability_dark_tunnel_site_ready), because = TYPE_PROC_REF(/mob/living, ability_dark_tunnel_site_text)),
				req(TYPE_PROC_REF(/mob/living, ability_can_afford_dark_tunnel), because = MSG(shadekin_ability/low_energy))),
			starts(TYPE_PROC_REF(/mob/living, ability_dark_tunnel_begins)),
			wait(DARK_TUNNEL_CHANNEL_TIME),
			then(TYPE_PROC_REF(/mob/living, ability_dark_tunneling))),
		op("dark_maw", label("Dark maw"), menu(button = "Dark maw", bind = "ability_shadekin_dark_maw"),
			needs(req_conscious(),
				req(TYPE_PROC_REF(/mob/living, ability_not_in_vr), because = MSG(shadekin_ability/vr)),
				req(TYPE_PROC_REF(/mob/living, ability_is_shadekin), because = MSG(shadekin_ability/not_shadekin)),
				req(TYPE_PROC_REF(/mob/living, ability_on_turf), because = MSG(shadekin_ability/no_turf)),
				req(TYPE_PROC_REF(/mob/living, ability_dark_enough_for_maw), because = MSG(shadekin_ability/too_bright_for_maw)),
				req(TYPE_PROC_REF(/mob/living, ability_can_afford_20), because = MSG(shadekin_ability/low_energy))),
			wait(1 SECOND),
			then(TYPE_PROC_REF(/mob/living, ability_dark_maw))),
		op("clear_dark_maws", label("Dispel dark maws"), menu(button = "Dispel dark maws", bind = "ability_shadekin_clear_dark_maws"),
			needs(req(TYPE_PROC_REF(/mob/living, ability_is_shadekin), because = MSG(shadekin_ability/not_shadekin))),
			then(TYPE_PROC_REF(/mob/living, ability_clear_dark_maws))))

/mob/living/proc/ability_dark_enough_for_maw(datum/act/op/A)
	var/turf/T = get_turf(src)
	return !!T && T.get_lumcount() < 0.5

/mob/living/proc/ability_can_afford_20(datum/act/op/A)
	var/datum/shadekin/SK = get_shadekin_state()
	return !!SK && SK.shadekin_get_energy() >= 20

/mob/living/proc/ability_dark_maw(datum/act/op/A)
	var/datum/shadekin/SK = get_shadekin_state()
	if(!SK)
		return OP_FAILED
	if(SK.in_phase)
		new /obj/effect/abstract/dark_maw(loc, src, TRUE)
	else
		new /obj/effect/abstract/dark_maw(loc, src)
	SK.shadekin_adjust_energy(-20)
	return OP_OK

/mob/living/proc/ability_clear_dark_maws(datum/act/op/A)
	var/datum/shadekin/SK = get_shadekin_state()
	if(!SK)
		return OP_FAILED
	for(var/obj/effect/abstract/dark_maw/dm as anything in SK.active_dark_maws?.Copy())
		dm.dispel()
	return OP_OK

/obj/effect/abstract/dark_maw
	var/mob/living/owner
	var/obj/belly/target
	var/has_signal = FALSE
	icon = 'icons/obj/Shadekin_powers.dmi'
	icon_state = "dark_maw_waiting"

/// TRUE while the maw lies in wait (placed, not yet triggered): it checks the light every 2 s and
/// dispels in the light.
/obj/effect/abstract/dark_maw/var/armed = FALSE
TRACKED(/obj/effect/abstract/dark_maw, armed)
CAPABILITIES(/obj/effect/abstract/dark_maw)
	every(2 SECONDS, then(PROC_REF(dark_maw_step)), when = nameof(armed))
	param(nameof(maw_user), pos = 1, keep = FALSE)
	param(nameof(trigger_now), pos = 2)

/// The shadekin who set the maw, and whether it springs at once (its constructor params).
/obj/effect/abstract/dark_maw/var/tmp/mob/maw_user
/obj/effect/abstract/dark_maw/var/trigger_now = FALSE

// ALLOW(init/INSTANCE_STATE): a maw binds to its shadekin, fizzles in light, snaps shut on whoever stands on it, or arms itself
/obj/effect/abstract/dark_maw/Initialize(mapload)
	var/mob/user = maw_user
	. = ..()
	if(!isturf(loc))
		return INITIALIZE_HINT_QDEL
	var/datum/shadekin/SK
	if(user && isliving(user))
		rel_set(src, nameof(owner), user)
		if(owner().vore_selected)
			rel_set(src, nameof(target), owner().vore_selected)
		observe(owner(), /datum/notice/qdeleting, src, then(PROC_REF(drop_everything_and_delete)))
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
			rel_add(SK, nameof(SK.active_dark_maws), src)
		flick("dark_maw", src)
		set_armed(TRUE)

///Called when we get a signal that our owner is being qdel'd
/obj/effect/abstract/dark_maw/proc/drop_everything_and_delete(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	spent(src)

/obj/effect/abstract/dark_maw/Crossed(O)
	. = ..()
	if(!isliving(O))
		return
	if(icon_state != "dark_maw_waiting")
		return
	var/mob/living/L = O
	if(!L.is_incorporeal() && (!owner() || L != owner()))
		triggered_by(L)

/obj/effect/abstract/dark_maw/proc/dark_maw_step(datum/act/timer/A)
	var/turf/T = get_turf(src)
	if(!istype(T) || T.get_lumcount() >= 0.5)
		dispel()

/obj/effect/abstract/dark_maw/proc/dispel()
	if(icon_state == "dark_maw_waiting")
		visible_message(span_notice("A set of shadowy lines flickers away in the light."))
	else
		visible_message(span_notice("The crystals and shadowy tendrils dissipate with the light shone on it."))
	icon_state = "dark_maw_used"
	spent(src)

/obj/effect/abstract/dark_maw/proc/triggered_by(mob/living/L, triggered_instantly = 0)
	set_armed(FALSE)
	icon_state = "dark_maw_used"
	flick("dark_maw_tr", src)
	L.status_adjust(STAT_STUNNED, 4)
	visible_message(span_warning("A set of crystals spring out of the ground and shadowy tendrils start wrapping around [L]."))
	if(owner() && !triggered_instantly)
		to_chat(owner(), span_warning("A dark maw you deployed has triggered!"))
	after(src, 1 SECOND, PROC_REF(do_trigger), with = list(L), keeps_dead = TRUE)

/obj/effect/abstract/dark_maw/proc/do_trigger(mob/living/L)
	var/will_vore = 1

	if(!(target() in owner()) || !can_phase_vore(owner(), L, TRUE))
		will_vore = 0

	if(!src || src.gc_destroyed)
		//We got deleted probably, do nothing more
		return

	if(!L || L.loc != get_turf(src))
		visible_message(span_notice("The shadowy tendrils fail to catch anything and dissipate."))
		spent(src, L)
		return

	if(will_vore)
		visible_message(span_warning("The shadowy tendrils grab around [L] and drag them into the floor, leaving nothing behind."))
		target().nom_atom(L)
		spent(src, L)
		return

	var/obj/effect/energy_net/dark/net = new /obj/effect/energy_net/dark(get_turf(src))
	if(net.buckle_mob(L))
		visible_message(span_warning("The shadowy tendrils wrap around [L] and traps them in a net of dark energy."))
	else
		visible_message(span_notice("The shadowy tendrils wrap around [L] and then dissipate, leaving them in place."))
	spent(src, L)

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
			act_message(user, src, others = span_danger("%U% dissipates %T% with a touch!"))
			unbuckle_mob(buckled_mob)
			return
	. = ..()

/obj/effect/energy_net/dark/periodic_step()
	. = ..()
	var/turf/T = get_turf(src)
	if(!istype(T) || T.get_lumcount() >= 0.6)
		visible_message(span_notice("The tangle of dark tendrils fades away in the light."))
		spent(src)

/// The shadekin who opened the maw (a relation view).
/obj/effect/abstract/dark_maw/proc/owner() as /mob/living
	return owner

/// The belly the maw feeds (a relation view).
/obj/effect/abstract/dark_maw/proc/target() as /obj/belly
	return target
