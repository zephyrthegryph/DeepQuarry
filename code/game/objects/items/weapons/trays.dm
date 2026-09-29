/*
 * Trays - Agouri
 */
/obj/item/tray
	name = "tray"
	icon = 'icons/obj/food.dmi'
	icon_state = "tray"
	desc = "A metal tray to lay food on."
	throwforce = 12.0
	throwforce = 10.0
	throw_speed = 1
	throw_range = 5
	w_class = ITEMSIZE_NORMAL
	MATERIAL_BULK(MAT_STEEL, 3000)
	var/list/carrying // List of things on the tray. - Doohl
	var/max_carry = 10
	var/min_bonus_damage = 3
	var/max_bonus_damage = 5
	COOLDOWN_DECLARE(shield_bash)
	drop_sound = 'sound/items/trayhit1.ogg'

/obj/item/tray/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	var/tray_sound = pick('sound/items/trayhit1.ogg', 'sound/items/trayhit2.ogg')
	user.setClickCooldown(user.get_attack_speed(src))
	// Drop all the things. All of them.
	cut_overlays()
	for(var/obj/item/I in carrying)
		I.forceMove(M.loc)
		LAZYREMOVE(carrying, I)
		if(isturf(I.loc))
			I.scatter_steps(rand(1, 2))


	if(CLUMSY_FAIL_CHANCE(user))              //What if he's a clown?
		to_chat(M, span_warning("You accidentally slam yourself with the [src]!"))
		M.status_at_least(EFFECT_WEAKENED, 1)
		user.injure(INJURY_BLUNT, 2, source = src)
		playsound(src, tray_sound, 50, 1)
		return ITEM_INTERACT_SUCCESS

	var/face_hit = FALSE

	if(!(user.zone_sel.selecting == O_EYES) && !(user.zone_sel.selecting == BP_HEAD) && !(user.zone_sel.selecting == O_MOUTH))
		add_attack_logs(user,M,"Hit with [src]")
		if(prob(15))
			M.status_at_least(EFFECT_WEAKENED, 3)

	else
		//attack_area = BP_HEAD //Ensure we're hitting a valid area.
		face_hit = TRUE //Our head is being hit! Let's presume we got hit in the face until we are told otherwise.
		for(var/slot in list(SLOT_ID_HEAD, SLOT_ID_MASK, SLOT_ID_EYES))
			var/obj/item/protection = M.get_equipped_item(slot)
			if(istype(protection) && (protection.body_parts_covered & FACE))
				face_hit = FALSE
				break


		if(face_hit) //No eye or head protection, tough luck!
			to_chat(M, span_warning("You get slammed in the face with the tray!"))
			M.injure(INJURY_BLUNT, rand(min_bonus_damage, max_bonus_damage), source = src) //This gets double damage. One here and one below.
			if(prob(30))
				M.status_at_least(EFFECT_STUNNED, rand(2,4))
			else if(prob(30))
				M.status_at_least(EFFECT_WEAKENED, 2)
		else
			to_chat(M, span_warning("You get slammed in the face with the tray, against your mask!"))
			if(M.get_equipped_item(SLOT_ID_MASK) && prob(33))
				M.get_equipped_item(SLOT_ID_MASK).add_blood(M)
			if(ishuman(M))
				var/mob/living/carbon/human/H = M
				if(H.get_equipped_item(SLOT_ID_HEAD) && prob(33))
					H.get_equipped_item(SLOT_ID_HEAD).add_blood(H)
				if(H.get_equipped_item(SLOT_ID_EYES) && prob(33))
					H.get_equipped_item(SLOT_ID_EYES).add_blood(H)

			if(prob(10))
				M.status_at_least(EFFECT_STUNNED, rand(1,3))
	if(prob(33))
		add_blood(M)
		var/turf/location = get_turf(M)
		if(issimulatedturf(location))
			location.add_blood(M)

	playsound(src, tray_sound, 50, 1)
	user.visible_message(span_danger("[user] slams [M] [face_hit ? "in the face " : ""]with the tray!"), runemessage = "CLANG!") // ALLOW(sys_visible_pair): passes a runemessage (chat bubble), which act_message does not carry
	M.injure(INJURY_BLUNT, rand(min_bonus_damage, max_bonus_damage), source = src)
	return ITEM_INTERACT_SUCCESS

DECLARE_INTERACTIONS(/obj/item/tray, INTERACT_ITEM(null, PROC_REF(interaction_item)))

/// Old attackby.
/obj/item/tray/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(istype(W, /obj/item/material/kitchen/rollingpin))
		if(!COOLDOWN_FINISHED(src, shield_bash))
			return INTERACTION_HANDLED_PASS
		act_message(user, src, others = span_warning("%U% bashes %T% with [W]!"))
		playsound(src, 'sound/effects/shieldbash.ogg', 50, 1)
		COOLDOWN_START(src, shield_bash, 2.5 SECONDS)
	else
		return FALSE
	return INTERACTION_HANDLED_PASS

/*
===============~~~~~================================~~~~~====================
=																			=
=  Code for trays carrying things. By Doohl for Doohl erryday Doohl Doohl~  =
=																			=
===============~~~~~================================~~~~~====================
*/
/obj/item/tray/proc/calc_carry()
	// calculate the weight of the items on the tray
	var/val = 0 // value to return

	for(var/obj/item/I in carrying)
		if(I.w_class == ITEMSIZE_TINY)
			val ++
		else if(I.w_class == ITEMSIZE_SMALL)
			val += 3
		else
			val += 5

	return val

/obj/item/tray/pickup(mob/user)

	if(!isturf(loc))
		return

	for(var/obj/item/I in contents_of(loc))
		if( I != src && !I.anchored && !istype(I, /obj/item/clothing/under) && !istype(I, /obj/item/clothing/suit) && !istype(I, /obj/item/projectile) )
			var/add = 0
			if(I.w_class == ITEMSIZE_TINY)
				add = 1
			else if(I.w_class == ITEMSIZE_SMALL)
				add = 3
			else
				add = 5
			if(calc_carry() + add >= max_carry)
				break
			var/image/Img = new(src.icon)
			I.forceMove(src)
			LAZYADD(carrying, I)
			Img.icon = I.icon
			Img.icon_state = I.icon_state
			Img.layer = layer + I.layer*0.01
			if(istype(I, /obj/item/material))
				var/obj/item/material/O = I
				if(O.applies_material_colour)
					Img.color = O.color
			add_overlay(Img)

/obj/item/tray/dropped(mob/user, equipping, slot)
	if(equipping)
		return ..() //Don't bother searching if we're just being put in a pocket/in hands.
	..()
	om_after(src, 0, PROC_REF(spill_where_dropped)) //Allows the tray to update location, rather than just checking against mob's location

/obj/item/tray/proc/spill_where_dropped()
	var/noTable = null
	if(isturf(loc) && !(locate_within(loc, /obj/structure/table)))
		noTable = 1

	if(isturf(loc) && !(locate_within(loc, /mob/living)))
		cut_overlays()
		for(var/obj/item/I in carrying)
			I.forceMove(loc)
			LAZYREMOVE(carrying, I)
			if(noTable)
				I.scatter_steps(rand(1, 2))
