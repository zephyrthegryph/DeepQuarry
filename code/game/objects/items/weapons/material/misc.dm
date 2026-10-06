/obj/item/material/harpoon
	name = "harpoon"
	sharp = TRUE
	edge = FALSE
	injury_kind = INJURY_PIERCE
	desc = "Tharr she blows!"
	icon_state = "harpoon"
	item_state = "harpoon"
	force_divisor = 0.3 // 18 with hardness 60 (steel)
	attack_verb = list("jabbed","stabbed","ripped")

/obj/item/material/knife/machete/hatchet
	name = "hatchet"
	desc = "A very sharp axe blade upon a short fibremetal handle. It has a long history of chopping things, but now it is used for chopping wood."
	icon = 'icons/obj/weapons.dmi'
	icon_state = "hatchet"
	force_divisor = 0.2 // 12 with hardness 60 (steel)
	thrown_force_divisor = 0.75 // 15 with weight 20 (steel)
	w_class = ITEMSIZE_SMALL
	sharp = TRUE
	edge = TRUE
	attack_verb = list("chopped", "torn", "cut")
	applies_material_colour = 0
	drop_sound = SFX_ITEMS_DROP_AXE
	pickup_sound = SFX_ITEMS_PICKUP_AXE
/* We have one already
/obj/item/material/knife/machete/hatchet/stone
	name = "sharp rock"
	desc = "The secret is to bang the rocks together, guys."
	force_divisor = 0.2
	icon_state = "rock"
	item_state = "rock"
	attack_verb = list("chopped", "torn", "cut")

/obj/item/material/knife/machete/hatchet/stone/set_material(new_material)
	var/old_name = name
	. = ..()
	name = old_name
*/
/obj/item/material/knife/machete/hatchet/unathiknife
	name = "duelling knife"
	desc = "A length of leather-bound wood studded with razor-sharp teeth. How crude."
	icon = 'icons/obj/weapons.dmi'
	icon_state = "unathiknife"
	attack_verb = list("ripped", "torn", "cut")
	can_cleave = FALSE

/obj/item/material/minihoe // -- Numbers
	name = "mini hoe"
	desc = "It's used for removing weeds or scratching your back."
	icon = 'icons/obj/weapons.dmi'
	icon_state = "hoe"
	force_divisor = 0.25 // 5 with weight 20 (steel)
	thrown_force_divisor = 0.25 // as above
	dulled_divisor = 0.75	//Still metal on a long pole
	w_class = ITEMSIZE_SMALL
	attack_verb = list("slashed", "sliced", "cut", "clawed")

/obj/item/material/snow/snowball
	name = "loose packed snowball"
	desc = "A fun snowball. Throw it at your friends!"
	icon = 'icons/obj/weapons.dmi'
	icon_state = "snowball"
	default_material = MAT_SNOW
	fragile = 1
	force_divisor = 0.01
	thrown_force_divisor = 0.10
	w_class = ITEMSIZE_SMALL
	attack_verb = list("mushed", "splatted", "splooshed", "splushed") // Words that totally exist.

CAPABILITIES(/obj/item/material/snow/snowball)
	op("compact", in_hand(), stance(I_HELP, I_DISARM, I_GRAB), label("Compact"), then(PROC_REF(interaction_self)))
	op("smash", in_hand(), stance(I_HURT), label("Smash"), then(PROC_REF(interaction_smash)))

/// Old attack_self: compacting it into a harder snowball.
/obj/item/material/snow/snowball/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_notice("You start compacting the snowball."))
	task_timed(user, 2 SECONDS, target = src, receiver = src, on_done = PROC_REF(attack_self_timed_done), done_args = list(user))
	return OP_OK

/// Old attack_self's harm branch: smashing it back into snow.
/obj/item/material/snow/snowball/proc/interaction_smash(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_notice("You smash the snowball in your hand."))
	var/atom/S = replace_with(src, /obj/item/stack/material/snow)
	user.put_in_hands(S)
	return OP_OK

/obj/item/material/snow/snowball/proc/attack_self_timed_done(mob/user)
	var/atom/S = replace_with(src, /obj/item/material/snow/snowball/reinforced)
	user.put_in_hands(S)

/obj/item/material/snow/snowball/reinforced
	name = "snowball"
	desc = "A well-formed and fun snowball. It looks kind of dangerous."
	force_divisor = 0.20
	thrown_force_divisor = 0.25

/obj/item/material/whip
	name = "whip"
	desc = "A tool used to discipline animals, or look cool. Mostly the latter."
	icon = 'icons/obj/weapons.dmi'
	icon_state = "whip"
	item_state = "chain"
	default_material = MAT_LEATHER
	slot_flags = SLOT_BELT
	w_class = ITEMSIZE_NORMAL
	attack_verb = list("flogged", "whipped", "lashed", "disciplined")
	force_divisor = 0.15
	thrown_force_divisor = 0.25
	reach = 2

	item_icons = list(
			slot_l_hand_str = 'icons/mob/items/lefthand_melee.dmi',
			slot_r_hand_str = 'icons/mob/items/righthand_melee.dmi',
			)

/obj/item/material/whip/afterattack(atom/A as mob|obj|turf|area, mob/user as mob, proximity)
	..()

	if(!proximity)
		return

	if(istype(A, /atom/movable))
		var/atom/movable/AM = A
		if(AM.anchored)
			to_chat(user, span_notice("\The [AM] won't budge."))
			return

		else
			if(!istype(AM, /obj/item))
				user.visible_message(span_warning("\The [AM] is pulled along by \the [src]!"))
				AM.Move(get_step(AM, get_dir(AM, src)))
				return

			else
				user.visible_message(span_warning("\The [AM] is snatched by \the [src]!"))
				AM.throw_at(user, reach, 0.1, user)

/obj/item/material/whip/apply_hit_effect(mob/living/target, mob/living/user, hit_zone, attack_modifier, stance = I_HURT)
	switch(stance)
		if(I_HURT)
			if(prob(10) && ishuman(target) && (user.zone_sel in list(BP_L_LEG, BP_R_LEG, BP_L_FOOT, BP_R_FOOT, BP_L_ARM, BP_R_ARM, BP_L_HAND, BP_R_HAND)))
				to_chat(target, span_warning("\The [src] rips at your hands!"))
				ranged_disarm(target)
		if(I_DISARM)
			if(prob(min(90, force * 3)) && ishuman(target) && (user.zone_sel in list(BP_L_LEG, BP_R_LEG, BP_L_FOOT, BP_R_FOOT, BP_L_ARM, BP_R_ARM, BP_L_HAND, BP_R_HAND)))
				ranged_disarm(target)
			else
				act_message(target, src, others = span_danger("%T% sends %U% stumbling away."))
				target.Move(get_step(target,get_dir(user,target)))
		if(I_GRAB)
			var/turf/STurf = get_turf(target)
			after(STurf, 0.2 SECONDS, TYPE_PROC_REF(/atom, om_playsound), with = list('sound/effects/snap.ogg', 60, 1))
			act_message(user, target, others = span_critical("\The [src] yanks %T% towards %U%!"))
			target.throw_at(get_turf(get_step(user,get_dir(user,target))), 2, 1, src)

	..()

/obj/item/material/whip/proc/ranged_disarm(mob/living/carbon/human/H, mob/living/user)
	if(istype(H))
		var/list/holding = list(H.get_active_hand() = 40, H.get_inactive_hand() = 20)

		if(user.zone_sel in list(BP_L_ARM, BP_R_ARM, BP_L_HAND, BP_R_HAND))
			for(var/obj/item/gun/W in holding)
				if(W && prob(holding[W]))
					var/list/turfs = list()
					for(var/turf/T in view())
						turfs += T
					if(turfs.len)
						var/turf/target = pick(turfs)
						visible_message(span_danger("[H]'s [W] goes off due to \the [src]!"))
						return W.afterattack(target,H)

		if(!(H.species.flags & NO_SLIP) && prob(10) && (user.zone_sel in list(BP_L_LEG, BP_R_LEG, BP_L_FOOT, BP_R_FOOT)))
			var/armor_check = H.armor_against(INJURY_BLUNT, user.zone_sel)
			H.apply_effect(3, WEAKEN, armor_check)
			play_sfx(src, SFX_WEAPONS_THUDSWOOSH)
			if(armor_check < 60)
				visible_message(span_danger("\The [src] has tripped [H]!"))
			else
				visible_message(span_warning("\The [src] attempted to trip [H]!"))
			return

		else
			if(H.break_all_grabs(user))
				play_sfx(src, SFX_WEAPONS_THUDSWOOSH)
				return

			if(user.zone_sel in list(BP_L_ARM, BP_R_ARM, BP_L_HAND, BP_R_HAND))
				for(var/obj/item/I in holding)
					if(I && prob(holding[I]))
						H.drop_from_inventory(I)
						visible_message(span_danger("\The [src] has disarmed [H]!"))
						play_sfx(src, SFX_WEAPONS_THUDSWOOSH)
						return

CAPABILITIES(/obj/item/material/whip)
	op("crack", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/material/whip/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	act_message(user, src, others = span_warning("%U% cracks %T%!"))
	play_sfx(src, SFX_EFFECTS_SNAP)
	return OP_OK


/obj/item/material/knife/machete/hatchet/stone
	name = "hatchet"
	desc = "A very sharp axe blade upon a short fibremetal handle. It has a long history of chopping things, but now it is used for chopping wood."
	icon = 'icons/obj/weapons_vr.dmi'
	icon_state = "stone_wood_axe"
	default_material = MAT_FLINT
	applies_material_colour = FALSE

/obj/item/material/knife/machete/hatchet/stone/bone
	icon_state = "stone_bone_axe"


//CHOMP Specific overrides
/obj/item/material/whip
	icon = 'icons/obj/weapons_ch.dmi'

/obj/item/material/butterfly/saw //This Saw Cleaver is in here since I do not know where else to put it
	name = "Saw Cleaver"
	desc = "A weapon consisting of a long handle and a heavy serrated blade. Using centrifrical force the blade extends outword allowing it to slice it long cleaves. The smell of blood hangs in the air around it."
	icon = 'icons/obj/weapons_ch.dmi'
	icon_state = "sawcleaver"
	item_icons = list(
			slot_l_hand_str = 'icons/mob/items/64x64_lefthand_ch.dmi',
			slot_r_hand_str = 'icons/mob/items/64x64_righthand_ch.dmi',
			)
	item_state = "cleaving_saw"
	active = 0
	attack_verb = list("attacked", "slashed", "stabbed", "sliced", "torn", "ripped", "diced", "cut")
	hitsound = SFX_WEAPONS_BLADESLICE
	w_class = ITEMSIZE_LARGE
	edge = 1
	sharp = 1
	injury_kind = INJURY_CUT
	force_divisor = 0.7 //42 When Wielded in line with a sword
	thrown_force_divisor = 0.1 // 2 when thrown with weight 20 (steel) since frankly its too bulk to throw

/obj/item/material/butterfly/saw/update_force()
	if(active)
		w_class = ITEMSIZE_HUGE
		can_cleave = 1
		force_divisor = 0.4 //24 when wielded, Gains cleave and is better than a machete
		icon_state = "sawcleaver_open"
		item_state = "cleaving_saw_open"
		..()
	else
		w_class = initial(w_class)
		can_cleave = initial(can_cleave)
		force_divisor = initial(force_divisor)
		icon_state = initial(icon_state)
		item_state = initial(item_state)
		..()
