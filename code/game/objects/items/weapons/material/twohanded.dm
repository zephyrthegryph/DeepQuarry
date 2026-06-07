/* Two-handed Weapons
 * Contains:
 * 		Twohanded
 *		Fireaxe
 *		Double-Bladed Energy Swords
 */

/*##################################################################
##################### TWO HANDED WEAPONS BE HERE~ -Agouri :3 ########
####################################################################*/

//Rewrote TwoHanded weapons stuff and put it all here. Just copypasta fireaxe to make new ones ~Carn
//This rewrite means we don't have two variables for EVERY item which are used only by a few weapons.
//It also tidies stuff up elsewhere.

/*
 * Twohanded
 */
/obj/item/material/twohanded
	w_class = ITEMSIZE_HUGE //CHOMP Edit
	var/wielded = 0
	var/force_wielded = 0
	var/force_unwielded
	var/wieldsound = null
	var/unwieldsound = null
	var/base_icon
	var/base_name
	var/unwielded_force_divisor = 0.25
	hitsound = "swing_hit"
	drop_sound = 'sound/items/drop/sword.ogg'
	pickup_sound = 'sound/items/pickup/sword.ogg'

/obj/item/material/twohanded/update_held_icon()
	var/mob/living/M = loc
	if(istype(M) && M.can_wield_item(src) && is_held_twohanded(M))
		wielded = 1
		force = force_wielded
		name = "[base_name] (wielded)"
		update_icon()
	else
		wielded = 0
		force = force_unwielded
		name = "[base_name]"
	update_icon()
	..()

/obj/item/material/twohanded/update_force()
	base_name = name
	if(sharp || edge)
		force_wielded = material.get_edge_damage()
	else
		force_wielded = material.get_blunt_damage()
	force_wielded = round(force_wielded*force_divisor)
	force_unwielded = round(force_wielded*unwielded_force_divisor)
	force = force_unwielded
	throwforce = round(force*thrown_force_divisor)
	//to_world("[src] has unwielded force [force_unwielded], wielded force [force_wielded] and throwforce [throwforce] when made from default material [material.name]")

/obj/item/material/twohanded/Initialize(mapload, material_key)
	. = ..()
	update_icon()

//Allow a small chance of parrying melee attacks when wielded - maybe generalize this to other weapons someday
/obj/item/material/twohanded/handle_shield(mob/user, damage, atom/damage_source = null, mob/attacker = null, def_zone = null, attack_text = "the attack")
	if(wielded && default_parry_check(user, attacker, damage_source) && prob(15))
		user.visible_message(span_danger("\The [user] parries [attack_text] with \the [src]!"))
		playsound(src, 'sound/weapons/punchmiss.ogg', 50, 1)
		return 1
	return 0

/obj/item/material/twohanded/update_icon()
	icon_state = "[base_icon][wielded]"
	item_state = icon_state

/obj/item/material/twohanded/dropped(mob/user, equipping, slot)
	if(equipping)
		return ..()
	..()
	if(wielded)
		spawn(0)
			update_held_icon()

/*
 * Fireaxe
 */
/obj/item/material/twohanded/fireaxe  // DEM AXES MAN, marker -Agouri
	icon_state = "fireaxe0"
	base_icon = "fireaxe"
	name = "fire axe"
	desc = "Truly, the weapon of a madman. Who would think to fight fire with an axe?"
	description_info = "This weapon can cleave, striking nearby lesser, hostile enemies close to the primary target.  It must be held in both hands to do this."
	unwielded_force_divisor = 0.25
	force_divisor = 0.7 // 10/42 with hardness 60 (steel) and 0.25 unwielded divisor
	dulled_divisor = 0.75	//Still metal on a stick
	sharp = TRUE
	edge = TRUE
	w_class = ITEMSIZE_LARGE
	slot_flags = SLOT_BACK
	force_wielded = 30
	attack_verb = list("attacked", "chopped", "cleaved", "torn", "cut")
	applies_material_colour = 0
	can_cleave = TRUE
	drop_sound = 'sound/items/drop/axe.ogg'
	pickup_sound = 'sound/items/pickup/axe.ogg'

/obj/item/material/twohanded/fireaxe/update_held_icon()
	var/mob/living/M = loc
	if(istype(M) && !issmall(M) && M.item_is_in_hands(src) && !M.hands_are_full())
		wielded = 1
		pry = 1
		force = force_wielded
		name = "[base_name] (wielded)"
		update_icon()
	else
		wielded = 0
		pry = 0
		force = force_unwielded
		name = "[base_name]"
	update_icon()
	..()

/obj/item/material/twohanded/fireaxe/afterattack(atom/A as mob|obj|turf|area, mob/user as mob, proximity)
	if(!proximity) return
	..()
	if(A && wielded)
		if(istype(A,/obj/structure/window/maintenance_panel))
			var/obj/structure/window/maintenance_panel/P = A
			P.take_damage(75,TRUE) // Not instant break, but still useful
		else if(istype(A,/obj/structure/window))
			var/obj/structure/window/W = A
			W.shatter()
		else if(istype(A,/obj/structure/grille))
			qdel(A)
		else if(istype(A,/obj/effect/plant))
			var/obj/effect/plant/P = A
			P.die_off()

/obj/item/material/twohanded/fireaxe/scythe
	icon_state = "scythe0"
	base_icon = "scythe"
	name = "scythe"
	desc = "A sharp and curved blade on a long fibremetal handle, this tool makes it easy to reap what you sow."
	force_divisor = 0.65
	attack_verb = list("chopped", "sliced", "cut", "reaped")

//spears, bay edition
/obj/item/material/twohanded/spear
	icon_state = "spearglass0"
	base_icon = "spearglass"
	name = "spear"
	desc = "A haphazardly-constructed yet still deadly weapon of ancient design."
	force = 10
	w_class = ITEMSIZE_HUGE //CHOMP Edit
	slot_flags = SLOT_BACK
	force_divisor = 0.5 			// 15 when wielded with hardness 30 (glass)
	unwielded_force_divisor = 0.375
	thrown_force_divisor = 1.5 		// 22.5 when thrown with weight 15 (glass)
	throw_speed = 3
	edge = FALSE
	sharp = TRUE
	hitsound = 'sound/weapons/bladeslice.ogg'
	mob_throw_hit_sound =  'sound/weapons/pierce.ogg'
	attack_verb = list("attacked", "poked", "jabbed", "torn", "gored")
	default_material = MAT_GLASS
	applies_material_colour = 0
	fragile = 1	//It's a haphazard thing of glass, wire, and steel
	reach = 2 // Spears are long.
	attackspeed = 14

//This is mostly for centaurs.
/obj/item/material/twohanded/spear/lance
	name = "lance"
	desc = "End him rightly"
	icon = 'icons/obj/weapons_vr.dmi'
	icon_state = "lance"
	item_state = "lance"
	force_divisor = 0.3
	force = 10
	thrown_force_divisor = 1
	default_material = "MAT_STEEL"
	fragile = 0
	sharp = TRUE
	edge = FALSE

/obj/item/material/twohanded/riding_crop
	name = "riding crop"
	desc = "A rod, a little over a foot long with a widened grip and a thick, leather patch at the end. Used since the dawn of the West to control animals."
	force_divisor = 0.05 //Required in order for the X attacks Y message to pop up.
	unwielded_force_divisor = 1 // One here, too.
	applies_material_colour = 1
	unbreakable = 1
	base_icon = "riding_crop"
	icon_state = "riding_crop0"
	attack_verb = list("cropped","spanked","swatted","smacked","peppered")

/obj/item/material/twohanded/spear/flint
	default_material = MAT_FLINT


// === merged from twohanded_ch.dm during hard-fork de-suffix (verified no override-order change) ===

/*
*
*Sledgehammer
*Mjollnir
*
*/

/obj/item/material/twohanded/sledgehammer  // a SLEGDGEHAMMER
	icon_state = "sledgehammer0"
	base_icon = "sledgehammer"
	name = "sledgehammer"
	desc = "A long, heavy hammer meant to be used with both hands. Typically used for breaking rocks and driving posts, it can also be used for breaking bones or driving points home."
	description_info = "This weapon can cleave, striking nearby lesser, hostile enemies close to the primary target.  It must be held in both hands to do this."
	unwielded_force_divisor = 0.25
	force = 25
	force_divisor = 0.9 // 10/42 with hardness 60 (steel) and 0.25 unwielded divisor
	hitsound = 'sound/weapons/heavysmash.ogg'
	icon = 'icons/obj/hammer_sprites_ch.dmi'
	w_class = ITEMSIZE_HUGE
	slowdown = 1.5
	dulled_divisor = 0.95	//Still metal on a stick
	sharp = 0
	edge = 0
	force_wielded = 23 //A fair bit less than the fireaxe.
	attack_verb = list("attacked", "smashed", "crushed", "wacked", "pounded")
	applies_material_colour = 0

	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_material_ch.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_material_ch.dmi',
		)

/obj/item/material/twohanded/sledgehammer/update_held_icon()
	var/mob/living/M = loc
	if(istype(M) && !issmall(M) && M.item_is_in_hands(src) && !M.hands_are_full())
		wielded = 1
		pry = 1
		force = force_wielded
		name = "[base_name] (wielded)"
		update_icon()
	else
		wielded = 0
		pry = 0
		force = force_unwielded
		name = "[base_name]"
	update_icon()
	..()

/obj/item/material/twohanded/sledgehammer/afterattack(atom/A as mob|obj|turf|area, mob/user as mob, proximity)
	if(!proximity) return
	..()
	if(A && wielded)
		if(istype(A,/obj/structure/window))
			var/obj/structure/window/W = A
			W.shatter()
		else if(istype(A,/obj/structure/grille))
			qdel(A)
		else if(istype(A,/obj/effect/plant))
			var/obj/effect/plant/P = A
			P.die_off()

// This cannot go into afterattack since some mobs delete themselves upon dying.
/obj/item/material/twohanded/sledgehammer/pre_attack(mob/living/target, mob/living/user)
	if(istype(target))
		cleave(user, target)

/obj/item/material/twohanded/sledgehammer/mjollnir
	icon_state = "mjollnir0"
	base_icon = "mjollnir"
	name = "Mjollnir"
	desc = "A long, heavy hammer. This weapons crackles with barely contained energy."
	force_divisor = 2
	hitsound = 'sound/effects/lightningbolt.ogg'
	force = 50
	throwforce = 15
	force_wielded = 75
	slowdown = 0

/obj/item/material/twohanded/sledgehammer/mjollnir/afterattack(atom/A as mob|obj|turf|area, mob/user as mob, proximity)
	..()

	if(proximity && wielded && isliving(A))
		var/mob/living/target = A
		if(prob(10))
			target.electrocute_act(500, src, def_zone = BP_TORSO)
			return
		if(prob(10))
			target.dust()
			return
		else
			target.stun_effect_act(10 , 50, BP_TORSO, src)
			target.take_organ_damage(10)
			target.Paralyse(20)
			playsound(src.loc, "sparks", 50, 1)
			return

/obj/item/material/twohanded/sledgehammer/mjollnir/update_icon()  //Currently only here to fuck with the on-mob icons.
	icon_state = "mjollnir[wielded]"
	return


// === merged from twohanded_vr.dm during hard-fork de-suffix (verified no override-order change) ===
//1R1S: Malady Blanche
/obj/item/material/twohanded/riding_crop/malady
	name = "Malady's riding crop"
	icon = 'icons/vore/custom_items_vr.dmi'
	item_icons = list(
				slot_l_hand_str = 'icons/vore/custom_items_left_hand_vr.dmi',
				slot_r_hand_str = 'icons/vore/custom_items_right_hand_vr.dmi',
				)
	desc = "An infernum made riding crop with Malady Blanche engraved in the shaft. It's a little worn from how many butts it has spanked."

/obj/item/material/twohanded/longsword
	w_class = ITEMSIZE_NORMAL
	name = "longsword"
	desc = "a more elegant weapon from a more civilised age"
	icon= 'icons/obj/weapons_vr.dmi'
	icon_state = "longsword"
	base_icon = "longsword"
	item_icons = list(
			slot_l_hand_str = 'icons/mob/items/lefthand_melee_vr.dmi',
			slot_r_hand_str = 'icons/mob/items/righthand_melee_vr.dmi',
			)
	item_state = "saber"
	unwielded_force_divisor = 0.1
	force_divisor = 0.3
	attack_verb = list("attacked", "slashed", "stabbed", "sliced", "torn", "ripped", "diced", "cut")
	edge = TRUE
	sharp = TRUE

/obj/item/material/twohanded/saber/handle_shield(mob/user, damage, atom/damage_source = null, mob/attacker = null, def_zone = null, attack_text = "the attack")
	if (src.wielded == 1)
		if(unique_parry_check(user, attacker, damage_source) && prob(50))
			user.visible_message(span_danger("\The [user] parries [attack_text] with \the [src]!"))
			playsound(src, 'sound/weapons/punchmiss.ogg', 50, 1)
		return 1
	return 0

/obj/item/material/twohanded/staff
	w_class = ITEMSIZE_LARGE
	default_material = MAT_WOOD
	name = "staff"
	desc = "A sturdy length of metal or wood. A common traveler's aid mostly used for support or probing unstable ground, but also a fairly effective weapon in a pinch."
	description_info = "When wielded with two hands, staves can be used to parry incoming melee attacks. Being on disarm intent also grants them an added chance to stun or knock down opponents, and increases your chances of parrying an attack."
	icon = 'icons/obj/weapons_vr.dmi'
	icon_state = "mat_staff"
	base_icon = "mat_staff"
	item_state = "mat_staff"
	item_icons = list(
			slot_l_hand_str = 'icons/mob/items/lefthand_melee_vr.dmi',
			slot_r_hand_str = 'icons/mob/items/righthand_melee_vr.dmi',
			)
	force_wielded = 18	//a bit stronger than a stun baton
	force_divisor = 0.45
	unwielded_force_divisor = 0.1
	var/base_parry_chance = 20
	var/disarm_defense = 1.5	//bonus multiplier to parry rate when in disarm stance
	var/stun_chance = 25	//chance to weaken an opponent when used in disarm stance only, remembering that disarm also halves damage dealt
	var/stun_duration = 2
	attack_verb = list("struck","smashed","thumped","thrashed","beaten","slammed","battered")
	edge = FALSE
	sharp = FALSE

/obj/item/material/twohanded/staff/handle_shield(mob/user, damage, atom/damage_source = null, mob/attacker = null, def_zone = null, attack_text = "the attack")
	var/parry_chance
	if(istype(damage_source, /obj/item/projectile))	//can't block ranged attacks, only melee!
		return 0
	if(src.wielded == 1)
		if(user.a_intent == I_DISARM)
			parry_chance = base_parry_chance * disarm_defense
		else
			parry_chance = base_parry_chance
		if(unique_parry_check(user, attacker, damage_source) && prob(parry_chance))
			user.visible_message(span_danger("\The [user] parries [attack_text] with \the [src]!"))
			playsound(src, 'sound/weapons/punchmiss.ogg', 50, 1)
			return 1
	return 0

/obj/item/material/twohanded/staff/apply_hit_effect(mob/living/target, mob/living/user, hit_zone)
	. = ..()
	if(src.wielded == 1 && user.a_intent == I_DISARM && prob(stun_chance))
		target.Weaken(stun_duration)
		user.visible_message(span_danger("\The [user] trips [target] with \the [src]!"))
