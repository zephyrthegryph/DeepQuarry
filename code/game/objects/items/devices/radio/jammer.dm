
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

	var/jam_range = 7
	var/obj/item/cell/device/weapon/power_source
	var/tick_cost = 5 // For the ERPs.

	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE

CAPABILITIES(/obj/item/radio_jammer)
	owns_one(nameof(power_source), /obj/item/cell/device/weapon, starts = /obj/item/cell/device/weapon)
	/// Drains its cell while switched on.
	every(2 SECONDS, then(PROC_REF(radio_jammer_step)), when = nameof(on))
	op("power", in_hand(), label("Toggle subspace jammer"), then(PROC_REF(jammer_power_requested)))
	op("hand", hand(), label("Use"), then(PROC_REF(interaction_hand)))
	op("item", item(/obj/item/cell/device/weapon), label("Insert cell"), then(PROC_REF(interaction_item)))

/obj/item/radio_jammer/var/on = FALSE
TRACKED(/obj/item/radio_jammer, on)

// a running jammer stops jamming.
/obj/item/radio_jammer/on_destroy(force)
	if(on)
		turn_off()
	..()

/obj/item/radio_jammer/get_cell()
	return power_source

REGISTRY_MEMBERSHIP(/obj/item/radio_jammer, REGISTRY_RADIO_JAMMERS)

/obj/item/radio_jammer/proc/turn_off(mob/user)
	if(user)
		to_chat(user,span_warning("\The [src] deactivates."))
	registry_leave(REGISTRY_RADIO_JAMMERS, src)
	set_on(FALSE)

/obj/item/radio_jammer/proc/turn_on(mob/user)
	if(user)
		to_chat(user,span_notice("\The [src] is now active."))
	registry_join(REGISTRY_RADIO_JAMMERS, src)
	set_on(TRUE)

/obj/item/radio_jammer/proc/radio_jammer_step(datum/act/timer/A)
	if(!power_source || !power_source.check_charge(tick_cost))
		var/mob/living/notify
		if(isliving(loc))
			notify = loc
		turn_off(notify)
	else
		power_source.use(tick_cost)


/obj/item/radio_jammer/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	if(user.get_inactive_hand() == src && power_source)
		to_chat(user,span_notice("You eject \the [power_source] from \the [src]."))
		user.put_in_hands(power_source)
		rel_take(src, nameof(power_source))
		turn_off()
		return TRUE
	return OP_DECLINE

/obj/item/radio_jammer/proc/jammer_power_requested(datum/act/op/A)
	var/mob/user = A.actor
	if(on)
		turn_off(user)
	else
		if(power_source)
			turn_on(user)
		else
			to_chat(user,span_warning("\The [src] has no power source!"))
	return OP_OK

/obj/item/radio_jammer/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(!power_source)
		if(!move_into(src, nameof(src.power_source), W, user))
			return TRUE
		to_chat(user,span_notice("You insert \the [power_source] into \the [src]."))
		return TRUE
	return OP_DECLINE

/obj/item/radio_jammer/draw(datum/look/look)
	..()
	if(on)
		look.state(active_state)
	look.overlay("jammer_overlay_[power_source ? between(0, round(power_source.percent(), 25), 100) : 0]")

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
