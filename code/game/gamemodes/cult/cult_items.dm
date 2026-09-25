/obj/item/melee/cultblade
	name = "cult blade"
	desc = "An arcane weapon wielded by the followers of Nar-Sie."
	icon_state = "cultblade"
	w_class = ITEMSIZE_LARGE
	force = 30
	throwforce = 10
	hitsound = 'sound/weapons/bladeslice.ogg'
	drop_sound = 'sound/items/drop/sword.ogg'
	pickup_sound = 'sound/items/pickup/sword.ogg'
	attack_verb = list("attacked", "slashed", "stabbed", "sliced", "torn", "ripped", "diced", "cut")
	edge = TRUE
	sharp = TRUE
	injury_kind = INJURY_CUT

/obj/item/melee/cultblade/cultify()
	return

/obj/item/melee/cultblade/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(iscultist(user) && !istype(user, /mob/living/simple_mob/construct))
		return ..()

	var/zone = (user.hand ? BP_L_ARM:BP_R_ARM)
	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		var/obj/item/organ/external/affecting = H.get_organ(zone)
		to_chat(user, span_danger("An inexplicable force rips through your [affecting.name], tearing the sword from your grasp!"))
		//random amount of damage between half of the blade's force and the full force of the blade.
		user.injure(INJURY_CUT, rand(force/2, force), zone, src)
		user.status_at_least(EFFECT_WEAKENED, 5)
	else if(!istype(user, /mob/living/simple_mob/construct))
		to_chat(user, span_danger("An inexplicable force rips through you, tearing the sword from your grasp!"))
	else
		to_chat(user, span_critical("The blade hisses, forcing itself from your manipulators. \The [src] will only allow mortals to wield it against foes, not kin."))

	user.drop_from_inventory(src, src.loc)
	throw_at(get_edge_target_turf(src, pick(GLOB.alldirs)), rand(1,3), throw_speed)

	var/spooky = pick('sound/hallucinations/growl1.ogg', 'sound/hallucinations/growl2.ogg', 'sound/hallucinations/growl3.ogg', 'sound/hallucinations/wail.ogg')
	playsound(src, spooky, 50, 1)

	return ITEM_INTERACT_SUCCESS

/obj/item/melee/cultblade/pickup(mob/living/user as mob)
	if(!iscultist(user) && !istype(user, /mob/living/simple_mob/construct))
		to_chat(user, span_warning("An overwhelming feeling of dread comes over you as you pick up the cultist's sword. It would be wise to be rid of this blade quickly."))
		user.status_adjust(EFFECT_DIZZY, 120)
	if(istype(user, /mob/living/simple_mob/construct))
		to_chat(user, span_warning("\The [src] hisses, as it is discontent with your acquisition of it. It would be wise to return it to a worthy mortal quickly."))

/obj/item/clothing/head/culthood
	name = "cult hood"
	icon_state = "culthood"
	desc = "A hood worn by the followers of Nar-Sie."
	flags_inv = HIDEFACE
	armor_spec = "melee=50;bullet=30;laser=50;energy=80;bomb=25;bio=10"
	min_cold_protection_temperature = SPACE_HELMET_MIN_COLD_PROTECTION_TEMPERATURE
	siemens_coefficient = 0

/obj/item/clothing/head/culthood/cultify()
	return

/obj/item/clothing/head/culthood/magus
	name = "magus helm"
	icon_state = "magus"
	desc = "A helm worn by the followers of Nar-Sie."
	flags_inv = HIDEFACE | BLOCKHAIR
	body_parts_covered = HEAD|FACE|EYES

/obj/item/clothing/head/culthood/alt
	icon_state = "cult_hoodalt"

/obj/item/clothing/suit/cultrobes
	name = "cult robes"
	desc = "A set of armored robes worn by the followers of Nar-Sie."
	icon_state = "cultrobes"
	body_parts_covered = UPPER_TORSO|LOWER_TORSO|LEGS|ARMS
	armor_spec = "melee=50;bullet=30;laser=50;energy=80;bomb=25;bio=10"
	flags_inv = HIDEJUMPSUIT
	siemens_coefficient = 0

/obj/item/clothing/suit/cultrobes/suit_storage_constraint()
	var/list/stores = list(POCKET_GENERIC, POCKET_EMERGENCY, POCKET_CULT)
	return list(HOLD_ONLY(stores))

/obj/item/clothing/suit/cultrobes/cultify()
	return

/obj/item/clothing/suit/cultrobes/alt
	icon_state = "cultrobesalt"

/obj/item/clothing/suit/cultrobes/magusred
	name = "magus robes"
	desc = "A set of armored robes worn by the followers of Nar-Sie."
	icon_state = "magusred"
	body_parts_covered = CHEST|LEGS|FEET|ARMS|HANDS
	flags_inv = HIDEGLOVES|HIDESHOES|HIDEJUMPSUIT

/obj/item/clothing/head/helmet/space/cult
	name = "cult helmet"
	desc = "A space worthy helmet used by the followers of Nar-Sie."
	icon_state = "cult_helmet"
	armor_spec = "melee=60;bullet=50;laser=30;energy=80;bomb=30;bio=30;rad=30;cold=60"
	siemens_coefficient = 0

/obj/item/clothing/head/helmet/space/cult/cultify()
	return

/obj/item/clothing/suit/space/cult
	name = "cult armour"
	icon_state = "cult_armour"
	desc = "A bulky suit of armour, bristling with spikes. It looks space-worthy."
	w_class = ITEMSIZE_NORMAL
	slowdown = 0.5
	armor_spec = "melee=60;bullet=50;laser=30;energy=80;bomb=30;bio=30;rad=30;cold=60"
	siemens_coefficient = 0
	flags_inv = HIDEGLOVES|HIDEJUMPSUIT|HIDETAIL|HIDETIE|HIDEHOLSTER

/obj/item/clothing/suit/space/cult/suit_storage_constraint()
	var/list/stores = list(POCKET_EMERGENCY, POCKET_SUIT_REGULATORS, POCKET_CULT)
	return list(HOLD_ONLY(stores))

/obj/item/clothing/suit/space/cult/cultify()
	return
