// Forged in the equivalent of Hell, one piece at a time.
/obj/item/stack/material/supermatter
	name = MAT_SUPERMATTER
	icon_state = "sheet-super"
	item_state = "diamond"
	default_type = MAT_SUPERMATTER
	apply_colour = TRUE
	COOLDOWN_DECLARE(event_cooldown)
	/// Mutex to prevent infinite recursion when propagating radiation pulses
	var/active = null

CAPABILITIES(/obj/item/stack/material/supermatter)
	every(2 SECONDS, then(PROC_REF(supermatter_step)))
	extend(/datum/act/hit/explosion, instead(then(PROC_REF(supermatter_blast_detonate))))
	op("pick_up", hand(), priority(OP_PRIORITY_DEFAULT), label("Pick up"), then(PROC_REF(supermatter_pick_up)))

/// Radiates only while a mob is close enough to be affected.
/obj/item/stack/material/supermatter/proc/supermatter_step(datum/act/timer/A)
	if(!mob_near(world.view))
		return
	radiate()

/obj/item/stack/material/supermatter/proc/radiate()
	if(active)
		return
	if(!COOLDOWN_FINISHED(src, event_cooldown))
		return
	active = TRUE
	radiation_pulse(
		src,
		max_range = (amount * 0.2), //10 range at 50 amount
		threshold = RAD_HEAVY_INSULATION,
		chance = URANIUM_IRRADIATION_CHANCE,
		minimum_exposure_time = NEBULA_RADIATION_MINIMUM_EXPOSURE_TIME,
		strength = amount * 0.5 //2 sheets = 1 rad, 50 sheets = 25 rads.
	)
	COOLDOWN_START(src, event_cooldown, 1.5 SECONDS)
	active = FALSE

/obj/item/stack/material/supermatter/proc/update_mass()	// Due to how dangerous they can be, the item will get heavier and larger the more are in the stack.
	slowdown = amount / 10
	set_w_class(min(5, round(amount / 10) + 1))
	throw_range = round(amount / 7) + 1

/obj/item/stack/material/supermatter/use(used)
	. = ..()
	update_mass()
	return

/// The stack's split question, then the touch burns as after any touch.
/obj/item/stack/material/supermatter/split_asked(datum/act/op/A)
	. = ..()
	if(. == OP_DECLINE)
		return
	supermatter_touched(A.actor)

/// Picking supermatter up: it re-weighs itself and may scorch the holder.
/obj/item/stack/material/supermatter/proc/supermatter_pick_up(datum/act/op/A)
	var/mob/living/user = A.actor
	pick_up_by_hand(user)
	supermatter_touched(user)
	return OP_OK

/// Old attack_hand's tail: after a touch, the stack re-weighs itself and may scorch the toucher.
/obj/item/stack/material/supermatter/proc/supermatter_touched(mob/user)
	update_mass()
	var/mob/living/M = user
	if(!istype(M))
		return

	M.receive_supermatter_contact(src)

/// An incredibly hard to manufacture material, SM chunks are unstable by their 'stabilized' nature: a blast can set the stack off.
/obj/item/stack/material/supermatter/proc/supermatter_blast_detonate(datum/act/hit/explosion/A)
	var/datum/damage_packet/packet = A.packet
	if(prob((4 / packet.severity) * 20))
		radiation_pulse(
			src,
			max_range = amount,
			threshold = RAD_HEAVY_INSULATION,
			chance = URANIUM_IRRADIATION_CHANCE * 5,
			minimum_exposure_time = 0,
			strength = amount * 10
			)
		explosion(get_turf(src),round(amount / 12) , round(amount / 6), round(amount / 3), round(amount / 25))
		destroyed(src, null, "explosion")
		return OP_OK
	return HOOK_DECLINE
