//replaces our stun baton code with /tg/station's code
/obj/item/melee/baton
	name = "stunbaton"
	desc = "A stun baton for incapacitating people with."
	icon_state = "stunbaton"
	item_state = "baton"
	slot_flags = SLOT_BELT
	force = 15
	sharp = FALSE
	edge = FALSE
	throwforce = 7
	flags = NOCONDUCT
	w_class = ITEMSIZE_NORMAL
	drop_sound = SFX_ITEMS_DROP_METALWEAPON
	pickup_sound = SFX_ITEMS_PICKUP_METALWEAPON
	attack_verb = list("beaten")
	var/lightcolor = "#FF6A00"
	var/stunforce = 0
	var/agonyforce = 60
	var/status = 0		//whether the thing is on or not
	var/obj/item/cell/bcell = null
	var/hitcost = 240
	var/grip_safety = TRUE
	var/taped_safety = FALSE

	///Var for attack_self chain
	var/special_handling = FALSE

CAPABILITIES(/obj/item/melee/baton)
	owns_one(nameof(bcell), /obj/item/cell)
	op("power", in_hand(), when(cond_not(nameof(special_handling))), label("Toggle baton"), then(PROC_REF(baton_power_toggled)))
	drag_onto(PROC_REF(mousedrop_input))
	op("take_cell", hand(), then(PROC_REF(interaction_hand)))
	op("baton_item", item(/obj/item), then(PROC_REF(interaction_item)))

/obj/item/melee/baton/Initialize(mapload)
	. = ..()
	update_icon()

/obj/item/melee/baton/get_cell()
	return bcell

/// The native MouseDrop's actor and arguments, handed over by the engine (drag_onto(), code/engine/lifeforms/input.dm).
/obj/item/melee/baton/proc/mousedrop_input(datum/act/input/A)
	if(!handle_inventory_drop(A.actor, A.over))
		return INPUT_FALLTHROUGH

/obj/item/melee/baton/proc/handle_inventory_drop(mob/user, obj/over_object)
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

CAPABILITIES(/obj/item/melee/baton/loaded)
	owns_one(nameof(bcell), /obj/item/cell, starts = /obj/item/cell/device/weapon) //this one starts with a cell pre-installed.

/obj/item/melee/baton/proc/deductcharge()
	if(status == 1)		//Only deducts charge when it's on
		if(bcell)
			if(bcell.checked_use(hitcost))
				return 1
			else
				return 0
	return null

/obj/item/melee/baton/proc/powercheck()
	if(bcell)
		if(bcell.charge < hitcost)
			status = 0
			update_icon()

DECLARE_APPEARANCE_PROC(/obj/item/melee/baton, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/melee/baton/appearance_overlays()
	. = list()
	if(status)
		icon_state = "[initial(name)]_active"
	else if(!bcell)
		icon_state = "[initial(name)]_nocell"
	else
		icon_state = "[initial(name)]"

	if(icon_state == "[initial(name)]_active")
		set_light(2, 1, lightcolor)
	else
		set_light(0)

/obj/item/melee/baton/dropped(mob/user, equipping, slot)
	..()
	if(status && grip_safety && !taped_safety)
		status = 0
		visible_message(span_warning("\The [src]'s grip safety engages!"))
	update_icon()

/obj/item/melee/baton/examine(mob/user)
	. = ..()

	if(Adjacent(user))
		if(taped_safety)
			. += span_warning("Someone has wrapped tape around the grip!")
		if(bcell)
			. += span_notice("The baton is [round(bcell.percent())]% charged.")
		if(!bcell)
			. += span_warning("The baton does not have a power source installed.")

/// Old attackby: fit a cell, tape down the grip safety, or scrape the tape off.
/obj/item/melee/baton/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(istype(W, /obj/item/cell))
		if(istype(W, /obj/item/cell/device))
			if(!bcell)
				if(!move_into(src, nameof(src.bcell), W, user))
					return OP_PASS
				to_chat(user, span_notice("You install a cell in [src]."))
				update_icon()
			else
				to_chat(user, span_notice("[src] already has a cell."))
		else
			to_chat(user, span_notice("This cell is not fitted for [src]."))
	if(istype(W, /obj/item/tape_roll) || istype(W, /obj/item/taperoll))
		if(grip_safety && !taped_safety)	//no point letting people wrap tape around the grips of batons without a safety
			to_chat(user, span_notice("You firmly wrap tape around the baton's grip, disabling the safety system."))
			play_sfx(src, SFX_EFFECTS_TAPE)
			taped_safety = TRUE
		else if(grip_safety && taped_safety)
			to_chat(user, span_notice("The grip safety has already been taped down."))
	if(W.has_tool_quality(TOOL_SCREWDRIVER))
		if(taped_safety)
			to_chat(user, span_notice("You painstakingly scrape away the tape over the grip safety."))
			taped_safety = FALSE
	return OP_PASS

/// Old attack_hand: the hand on a baton held in the other hand takes its cell out (anything else is the pick up).
/obj/item/melee/baton/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	if(user.get_inactive_hand() == src)
		if(bcell)
			bcell.update_icon()
			user.put_in_hands(bcell)
			own_take(src, nameof(bcell))
			to_chat(user, span_notice("You remove the cell from the [src]."))
			status = 0
			update_icon()
			return OP_OK
		return OP_DECLINE
	else
		return OP_DECLINE
	return OP_DECLINE

/obj/item/melee/baton/proc/baton_power_toggled(datum/act/op/A)
	var/mob/user = A.actor
	if(bcell && bcell.charge >= hitcost)
		status = !status
		to_chat(user, span_notice("[src] is now [status ? "on" : "off"]."))
		play_sfx(src, SFX_SPARKS, 1.5, extrarange = -1)
		update_icon()
	else
		status = 0
		if(!bcell)
			to_chat(user, span_warning("[src] does not have a power source!"))
		else
			to_chat(user, span_warning("[src] is out of charge."))
	add_fingerprint(user)
	return OP_OK

/obj/item/melee/baton/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(status && CLUMSY_FAIL_CHANCE(user))
		to_chat(user, span_danger("You accidentally hit yourself with the [src]!"))
		user.status_at_least(STAT_WEAKENED, 30)
		deductcharge()
		return ITEM_INTERACT_SUCCESS
	deductcharge()
	return ..()

/obj/item/melee/baton/apply_hit_effect(mob/living/target, mob/living/user, hit_zone, attack_modifier, stance = I_HURT)
	if(isrobot(target))
		return ..()

	var/agony = agonyforce
	var/stun = stunforce
	var/obj/item/organ/external/affecting = null
	if(ishuman(target))
		var/mob/living/carbon/human/H = target
		affecting = H.get_organ(hit_zone)

	if(stance == I_HURT) // No disarm. ONLY HARM.
		. = ..()
		//whacking someone causes a much poorer electrical contact than deliberately prodding them.
		agony *= 0.5
		stun *= 0.5
	else if(!status)
		if(affecting)
			act_message(user, target, others = span_warning("%T% has been prodded in the [affecting.name] with [src] by %U%. Luckily it was off."))
		else
			act_message(user, target, others = span_warning("%T% has been prodded with [src] by %U%. Luckily it was off."))
	else
		if(affecting)
			act_message(user, target, others = span_danger("%T% has been prodded in the [affecting.name] with [src] by %U%!"))
		else
			act_message(user, target, others = span_danger("%T% has been prodded with [src] by %U%!"))
		play_sfx(src, SFX_WEAPONS_EGLOVES)

	//stun effects
	if(status)
		target.stun_effect_act(stun, agony, hit_zone, src, electric = TRUE)
		msg_admin_attack("[key_name(user)] stunned [key_name(target)] with the [src].")

		if(ishuman(target))
			var/mob/living/carbon/human/H = target
			H.forcesay(GLOB.hit_appends)
	powercheck()

//Makeshift stun baton. Replacement for stun gloves.
/obj/item/melee/baton/cattleprod
	name = "stunprod"
	desc = "An improvised stun baton."
	icon_state = "stunprod_nocell"
	item_state = "prod"
	force = 3
	throwforce = 5
	stunforce = 0
	agonyforce = 60	//same force as a stunbaton, but uses way more charge.
	hitcost = 2500	//runs off the same kind of big batteries as APCs, not small cells!
	attack_verb = list("poked")
	slot_flags = null
	grip_safety = FALSE

CAPABILITIES(/obj/item/melee/baton/cattleprod)
	op("cattleprod_interaction_item", item(/obj/item), then(PROC_REF(cattleprod_interaction_item)))
	without("baton_item")   // its own item use replaces the baton's

/// Old attackby.
/obj/item/melee/baton/cattleprod/proc/cattleprod_interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(istype(W, /obj/item/cell))
		if(!istype(W, /obj/item/cell/device))
			if(!bcell)
				if(!move_into(src, nameof(src.bcell), W, user))
					return OP_PASS
				to_chat(user, span_notice("You install a cell in [src]."))
				update_icon()
			else
				to_chat(user, span_notice("[src] already has a cell."))
		else
			to_chat(user, span_notice("This cell is not fitted for [src]."))
	return OP_PASS

/obj/item/melee/baton/get_description_interaction()
	var/list/results = list()

	if(bcell)
		results += "[desc_panel_image("offhand")]to remove the weapon cell."
	else
		results += "[desc_panel_image("weapon cell")]to add a new weapon cell."

	results += ..()

	return results

// Rare version of a baton that causes lesser lifeforms to really hate the user and attack them.
/obj/item/melee/baton/shocker
	name = "shocker"
	desc = "A device that appears to arc electricity into a target to incapacitate or otherwise hurt them, similar to a stun baton.  It looks inefficent."
	icon_state = "shocker"
	force = 10
	throwforce = 5
	agonyforce = 25 // Less efficent than a regular baton.
	attack_verb = list("poked")

/obj/item/melee/baton/shocker/apply_hit_effect(mob/living/target, mob/living/user, hit_zone, attack_modifier, stance = I_HURT)
	..(target, user, hit_zone, attack_modifier, stance)
	if(status && (target.ai_brain != null))
		target.taunt(user)
