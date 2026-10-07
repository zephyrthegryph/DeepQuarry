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

DECLARE_PERIODIC(/obj/item/stack/material/supermatter, PERIODIC_SLOW)

/// Radiates only while a mob is close enough to be affected; otherwise it sleeps until one comes near.
/obj/item/stack/material/supermatter/periodic_step()
	if(!mob_near(world.view))
		return sleep_until_mob_near(world.view)
	radiate()
	..()

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
	w_class = min(5, round(amount / 10) + 1)
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

EXTEND_INTERACTIONS(/obj/item/stack/material/supermatter, INTERACT_HAND_DEFAULT("Pick up", PROC_REF(supermatter_pick_up)))

/// Picking supermatter up: it re-weighs itself and may scorch the holder.
/obj/item/stack/material/supermatter/proc/supermatter_pick_up(mob/user, obj/item/held, datum/interaction/interaction)
	. = TRUE
	interaction_pick_up(user, held, interaction)
	supermatter_touched(user)

/// Old attack_hand's tail: after a touch, the stack re-weighs itself and may scorch the toucher.
/obj/item/stack/material/supermatter/proc/supermatter_touched(mob/user)
	update_mass()
	var/mob/living/M = user
	if(!istype(M))
		return

	var/burn_user = TRUE
	if(ishuman(M))
		var/mob/living/carbon/human/H = user
		var/obj/item/clothing/gloves/G = H.get_equipped_item(SLOT_ID_GLOVES)
		if(istype(G) && ((G.flags & THICKMATERIAL && prob(70)) || istype(G, /obj/item/clothing/gloves/gauntlets)))
			burn_user = FALSE

		if(burn_user)
			act_message(src, H, others = span_danger("%U% flashes as it scorches %T%'s hands!"))
			H.injure(INJURY_BURN, amount / 2 + 5, BP_R_HAND, src)
			H.injure(INJURY_BURN, amount / 2 + 5, BP_L_HAND, src)
			H.drop_from_inventory(src, get_turf(H))
			return

	if(isrobot(user))
		burn_user = FALSE

	if(burn_user)
		M.injure(INJURY_BURN, amount, null, src)

CAPABILITIES(/obj/item/stack/material/supermatter)
	extend(/datum/act/hit/explosion, instead(then(PROC_REF(supermatter_blast_detonate))))

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
