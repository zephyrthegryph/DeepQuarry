
/proc/is_jammed(obj/radio)
	var/turf/Tr = get_turf(radio)
	if(!Tr) return 0 //Nullspace radios don't get jammed.

	var/area/our_area = get_area(Tr)

	if(our_area.no_comms)
		return TRUE

	for(var/obj/item/radio_jammer/J as anything in REGISTRY_MEMBERS(REGISTRY_RADIO_JAMMERS))
		var/turf/Tj = get_turf(J)

		if(J.on && Tj && Tj.z == Tr.z) //If we're on the same Z, it's worth checking.
			var/dist = get_dist(Tj,Tr)
			if(dist <= J.jam_range)
				return list("jammer" = J, "distance" = dist)

/obj/item/radio_jammer
	name = "subspace jammer"
	desc = "Primarily for blocking subspace communications, preventing the use of headsets, PDAs, and communicators. Also masks suit sensors."	// Added suit sensor jamming
	icon = 'icons/obj/device.dmi'
	icon_state = "jammer0"
	var/active_state = "jammer1"
	var/last_overlay_percent = null // Stores overlay icon_state to avoid excessive recreation of overlays.

	var/on = 0
	var/jam_range = 7
	var/obj/item/cell/device/weapon/power_source
	var/tick_cost = 5 // For the ERPs.

	pickup_sound = 'sound/items/pickup/device.ogg'
	drop_sound = 'sound/items/drop/device.ogg'

/obj/item/radio_jammer/Initialize(mapload)
	. = ..()
	power_source = new(src)
	update_icon() // So it starts with the full overlay.

REF_OWNED(/obj/item/radio_jammer, "power_source")

// LIFECYCLE: a running jammer stops jamming.
/obj/item/radio_jammer/Destroy()
	if(on)
		turn_off()
	return ..()

/obj/item/radio_jammer/get_cell()
	return power_source

REGISTRY_MEMBERSHIP(/obj/item/radio_jammer, REGISTRY_RADIO_JAMMERS)

/obj/item/radio_jammer/proc/turn_off(mob/user)
	if(user)
		to_chat(user,span_warning("\The [src] deactivates."))
	PERIODIC_STOP(src)
	registry_leave(REGISTRY_RADIO_JAMMERS, src)
	on = FALSE
	update_icon()

/obj/item/radio_jammer/proc/turn_on(mob/user)
	if(user)
		to_chat(user,span_notice("\The [src] is now active."))
	PERIODIC_START(src, PERIODIC_SLOW)
	registry_join(REGISTRY_RADIO_JAMMERS, src)
	on = TRUE
	update_icon()

/obj/item/radio_jammer/periodic_step()
	if(!power_source || !power_source.check_charge(tick_cost))
		var/mob/living/notify
		if(isliving(loc))
			notify = loc
		turn_off(notify)
	else
		power_source.use(tick_cost)
		update_icon()


/obj/item/radio_jammer/get_interactions()
	var/static/list/L = list(
		INTERACT_HAND(null, PROC_REF(interaction_hand)),
		INTERACT_USE(null, PROC_REF(interaction_self)),
		INTERACT_INSERT(/obj/item/cell/device/weapon, PROC_REF(interaction_item), "Insert cell"),
	)
	return L

/obj/item/radio_jammer/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	if(user.get_inactive_hand() == src && power_source)
		to_chat(user,span_notice("You eject \the [power_source] from \the [src]."))
		user.put_in_hands(power_source)
		power_source = null
		turn_off()
		return TRUE
	return FALSE

/obj/item/radio_jammer/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(on)
		turn_off(user)
	else
		if(power_source)
			turn_on(user)
		else
			to_chat(user,span_warning("\The [src] has no power source!"))

/obj/item/radio_jammer/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(!power_source)
		power_source = W
		power_source.update_icon() //Why doesn't a cell do this already? :|
		user.unEquip(power_source)
		power_source.forceMove(src)
		update_icon()
		to_chat(user,span_notice("You insert \the [power_source] into \the [src]."))
		return TRUE
	return FALSE

/obj/item/radio_jammer/update_icon()
	if(on)
		icon_state = active_state
	else
		icon_state = initial(icon_state)

	var/overlay_percent = 0
	if(power_source)
		overlay_percent = between(0, round( power_source.percent() , 25), 100)
	else
		overlay_percent = 0

	// Only Cut() if we need to.
	if(overlay_percent != last_overlay_percent)
		cut_overlays()
		add_overlay("jammer_overlay_[overlay_percent]")
		last_overlay_percent = overlay_percent

//Unlimited use, unlimited range jammer for admins. Turn it on, drop it somewhere, it works.
/obj/item/radio_jammer/admin
	jam_range = 255
	tick_cost = 0

///Checks to see if the clothing is in a belly that jams sensors or blocks tracking.
/proc/is_vore_jammed(atom/current)
	while(current.loc)
		if(isbelly(current.loc))
			var/obj/belly/B = current.loc
			if(B.mode_flags & DM_FLAG_JAMSENSORS)
				return TRUE
		current = current.loc
	return FALSE
