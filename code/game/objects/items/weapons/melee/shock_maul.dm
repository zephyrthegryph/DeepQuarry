/obj/item/melee/shock_maul
	name = "concussion maul"
	desc = "A heavy-duty concussion hammer typically used for mining, as it can pulverize and break rocks without damaging denser ores if used correctly. If used incorrectly, there are very few things it cannot smash; this fact made it an iconic weapon for the many uprisings of Mars. It uses a manually engaged concussive-force amplifier unit in the head to multiply impact power, but its weight and the charge up time makes it difficult to use effectively. Devastating if used correctly, but requires skill. It also appears to have a sling attached, so that you can carry it on your back if you need to."
	icon_state = "forcemaul"
	item_state = "forcemaul"
	slot_flags = SLOT_BACK

	//stopping power/lethality
	force = 35
	armor_penetration = 20		//the sheer impact force bypasses quite a bit of armour
	var/unwielded_force_divisor = 0.25
	var/wielded = 0
	var/force_unwielded = 8.75
	var/wieldsound = null
	var/unwieldsound = null
	var/charge_time = 2 SECONDS		//how long it takes to charge the hammer
	var/charge_force_mult = 1.75	//damage and AP multiplier on charged hits
	var/launch_force = 3	//yeet distance
	var/launch_force_unwielded = 1	//awful w/ one hand, but still gets a little distance
	var/launch_force_disarm = 1.5	//distance multiplier when swinging in disarm mode, since disarm attacks do half damage
	var/weaken_force = 2	//stun power
	var/weaken_force_unwielded = 0	//can't stun at all if used onehanded
	var/weaken_force_disarm = 1.5	//stun multiplier when in disarm mode

	//mining interacts
	var/excavation_amount = 200
	var/destroy_artefacts = TRUE	//sorry, breaks stuff

	can_cleave = TRUE	//SSSSMITE!
	attackspeed = 12	//very slow!!
	sharp = FALSE
	edge = FALSE
	throwforce = 25
	flags = NOCONDUCT
	w_class = ITEMSIZE_HUGE
	drop_sound = SFX_ITEMS_DROP_METALWEAPON
	pickup_sound = SFX_ITEMS_PICKUP_METALWEAPON
	attack_verb = list("beaten","slammed","smashed","mauled","hammered","bludgeoned")
	var/lightcolor = "#D3FDFD"
	var/status = 0		//whether the thing is on or not
	var/obj/item/cell/bcell = null
	var/hitcost = 400	//you get 6 hits out of a standard cell

/obj/item/melee/shock_maul/update_held_icon()
	var/mob/living/M = loc
	if(istype(M) && M.can_wield_item(src) && is_held_twohanded(M))
		wielded = 1
		if(status)
			force = initial(force)*charge_force_mult
			armor_penetration *= charge_force_mult
		else
			force = initial(force)
			armor_penetration = initial(armor_penetration)
		launch_force = initial(launch_force)
		weaken_force = initial(weaken_force)
		name = "[initial(name)] (wielded)"
		changed(src)
		changed(src)
	else
		wielded = 0
		if(status)
			force = force_unwielded*charge_force_mult
			armor_penetration *= charge_force_mult
		else
			force = force_unwielded
			armor_penetration = initial(armor_penetration)
		launch_force = launch_force_unwielded
		weaken_force = weaken_force_unwielded
		name = "[initial(name)]"
	changed(src)
	changed(src)
	..()

/obj/item/melee/shock_maul/Initialize(mapload)
	. = ..()
	update_held_icon()

/obj/item/melee/shock_maul/get_cell()
	return bcell

/// The native MouseDrop's actor and arguments, handed over by the engine (drag_onto(), code/engine/lifeforms/input.dm).
/obj/item/melee/shock_maul/proc/mousedrop_input(datum/act/input/A)
	if(!handle_inventory_drop(A.actor, A.over))
		return INPUT_FALLTHROUGH

/obj/item/melee/shock_maul/proc/handle_inventory_drop(mob/user, obj/over_object)
	if(!canremove)
		return TRUE

	if (ishuman(user) || issmall(user)) //so monkeys can take off their backpacks -- Urist

		if (istype(user.loc,/obj/mecha)) // stops inventory actions in a mech. why?
			return TRUE

		if (!( istype(over_object, /atom/movable/screen) ))
			return FALSE

		//makes sure that the thing is equipped, so that we can't drag it into our hand from miles away.
		//there's got to be a better way of doing this.
		if (!(src.loc == user) || (src.loc && src.loc.loc == user))
			return TRUE

		if (( user.restrained() ) || ( user.stat ))
			return TRUE

		if ((src.loc == user) && !(istype(over_object, /atom/movable/screen)) && !user.unEquip(src))
			return TRUE

		switch(over_object.name)
			if("r_hand")
				user.put_in_r_hand(src)
			if("l_hand")
				user.put_in_l_hand(src)
		src.add_fingerprint(user)
	return TRUE

/obj/item/melee/shock_maul/loaded/ownership()
	. = ..()
	. += owns(nameof(bcell), policy = OWN_CONTAINED, starts = /obj/item/cell/device/weapon)

	changed(src)
/obj/item/melee/shock_maul/proc/deductcharge()
	if(status == 1)		//Only deducts charge when it's on
		if(bcell)
			if(bcell.checked_use(hitcost))
				return 1
			else
				return 0
	return null

/obj/item/melee/shock_maul/proc/powercheck()
	if(bcell)
		if(bcell.charge < hitcost)
			status = 0
			update_held_icon()

/obj/item/melee/shock_maul/draw(datum/look/look)
	..()
	var/drawn_state = look.state_so_far(src)
	if(status)
		drawn_state = look.state("[initial(icon_state)]_active[wielded]")
		look.held_state(drawn_state)
	else if(!bcell)
		drawn_state = look.state("[initial(icon_state)]_nocell[wielded]")
		look.held_state(drawn_state)
	else
		drawn_state = look.state("[initial(icon_state)][wielded]")
		look.held_state(drawn_state)

	if(drawn_state == "[initial(icon_state)]_active[wielded]")
		look.light(2, 1, lightcolor)
	else
		look.light_off()

/obj/item/melee/shock_maul/dropped(mob/user, equipping, slot)
	..()
	if(status)
		status = 0
		visible_message(span_warning("\The [src]'s grip safety engages!"))
	update_held_icon()

/obj/item/melee/shock_maul/examine(mob/user)
	. = ..()

	if(Adjacent(user))
		if(bcell)
			. += span_notice("The concussion maul is [round(bcell.percent())]% charged.")
		if(!bcell)
			. += span_warning("The concussion maul does not have a power source installed.")

/// Old attackby.
/obj/item/melee/shock_maul/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(!user.IsAdvancedToolUser())
		return OP_PASS
	if(istype(W, /obj/item/cell))
		if(istype(W, /obj/item/cell/device))
			if(!bcell)
				if(!move_into(src, nameof(src.bcell), W, user))
					return OP_PASS
				to_chat(user, span_notice("You install a cell in \the [src]."))
				update_held_icon()
			else
				to_chat(user, span_notice("\The [src] already has a cell."))
		else
			to_chat(user, span_notice("This cell is not fitted for [src]."))
	return OP_PASS

CAPABILITIES(/obj/item/melee/shock_maul)
	op("hand", hand(), label("Use"), then(PROC_REF(interaction_hand)))
	op("self", in_hand(), label("Use"), then(PROC_REF(interaction_self)))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))
	on_notice(/datum/notice/hit/emp, then(PROC_REF(shock_maul_emp)))
	drag_onto(PROC_REF(mousedrop_input))

/// Old attack_hand.
/obj/item/melee/shock_maul/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	if(user.get_inactive_hand() == src)
		if(!user.IsAdvancedToolUser())
			return TRUE
		else if(bcell)
			bcell.update_icon()
			user.put_in_hands(bcell)
			rel_take(src, nameof(bcell))
			to_chat(user, span_notice("You remove the cell from the [src]."))
			status = 0
			update_held_icon()
			return TRUE
		return OP_DECLINE
	else
		return OP_DECLINE

/// Old attack_self.
/obj/item/melee/shock_maul/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(!user.IsAdvancedToolUser())
		return TRUE
	if(!status && bcell && bcell.charge >= hitcost)
		om_task_timed(user, charge_time, target = src, receiver = src, on_done = PROC_REF(attack_self_timed_done), done_args = list(user))
	else if(status)
		status = 0
		act_message(user, src, MSG_SELF(span_notice("%T% is now off.")), MSG_OTHERS(span_notice("%U% safely disengages %T%'s power field.")))
		update_held_icon()
		play_sfx(src, SFX_SPARKS, 1.5, extrarange = -1)
		if(!bcell)
			to_chat(user, span_warning("\The [src] does not have a power source!"))
	else
		to_chat(user, span_warning("\The [src] is out of charge."))
	add_fingerprint(user)
	return TRUE

/obj/item/melee/shock_maul/proc/attack_self_timed_done(mob/user)
	status = 1
	act_message(user, src, MSG_SELF(span_warning("You charge %T%. <b>It's hammer time!</b>")), MSG_OTHERS(span_warning("%U% charges %T%!")))
	play_sfx(src, SFX_SPARKS, 1.5, extrarange = -1)
	update_held_icon()

/obj/item/melee/shock_maul/afterattack(atom/A as mob|obj|turf|area, mob/user as mob, proximity)
	if(!proximity) return
	..()
	// start - maul changes
	if(A && wielded && status)
		if(istype(A,/obj/structure/window))
			var/obj/structure/window/W = A
			visible_message(span_warning("\The [W] crumples under the force of the impact!"))
			W.shatter()
		else if(istype(A,/obj/structure/barricade))
			var/obj/structure/barricade/B = A
			visible_message(span_warning("\The [B] crumples under the force of the impact!"))
			B.dismantle()
		else if(istype(A,/obj/structure/grille))
			visible_message(span_warning("\The [A] crumples under the force of the impact!"))
			consumed(A, src)
		else if(istype(A, /turf/simulated/wall))
			var/turf/simulated/wall/W = A
			if(W.density)
				W.take_damage(force*3)	//One hit for regular walls, 3 hits for r_wall
		else if(istype(A, /obj/structure/girder))
			var/obj/structure/girder/G = A
			G.dismantle()
		else
			return ..()	//Don't do anything if we don't resolve anything on our target
		deductcharge()
		status = 0
		user.visible_message(span_warning("\The [src] discharges with a thunderous, hair-raising crackle!"))
		play_sfx(src, SFX_WEAPONS_RESONATOR_BLAST)
		update_held_icon()
		powercheck(hitcost)
	// end

/obj/item/melee/shock_maul/apply_hit_effect(mob/living/target, mob/living/user, hit_zone, attack_modifier, stance = I_HURT)
	. = ..()
	if(stance == I_DISARM)
		launch_force *= launch_force_disarm
		weaken_force *= weaken_force_disarm

	//yeet 'em away, boys!
	if(status)
		var/atom/target_zone = get_edge_target_turf(user,get_dir(user, target))
		if(!target.anchored)	//unless they're secured in place, natch
			target.throw_at(target_zone, launch_force, 2, user, FALSE)
		target.status_at_least(STAT_WEAKENED, weaken_force)

		deductcharge()
		status = 0
		user.visible_message(span_warning("\The [src] discharges with a thunderous, hair-raising crackle!"))
		play_sfx(src, SFX_WEAPONS_RESONATOR_BLAST)
		update_held_icon()
	powercheck(hitcost)

/// An EMP kills the power field.
/obj/item/melee/shock_maul/proc/shock_maul_emp(datum/act/A)
	if(!status)
		return
	status = FALSE
	visible_message(span_warning("\The [src]'s power field hisses and sputters out."))
	update_held_icon()

/obj/item/melee/shock_maul/get_description_interaction()
	var/list/results = list()

	if(bcell)
		results += "[desc_panel_image("offhand")]to remove the weapon cell."
	else
		results += "[desc_panel_image("weapon cell")]to add a new weapon cell."

	results += ..()

	return results


/obj/item/melee/shock_maul/harmless
	name = "rubber concussion maul"
	desc = "A variant of the concussion maul that staggers and weakens victims. Despite their screams, does no real damage."
	injury_kind = INJURY_PAIN
	launch_force = 0

/obj/item/melee/shock_maul/ownership()
	. = ..()
	. += owns(nameof(bcell), policy = OWN_CONTAINED)
