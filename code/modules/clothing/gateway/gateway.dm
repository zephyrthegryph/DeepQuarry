//vr section
/obj/item/clothing/head/vrwizard
	name = "wizard hat"
	desc = "A pointy pixelated-looking hat, 0s and 1s dancing off the fabric"
	icon_state = "redwizard"
	armor_spec = "melee=20;bullet=20;laser=60;energy=60;bomb=70;bio=50;rad=50"
	siemens_coefficient = 0.1
	cold_protection = HEAD
	min_cold_protection_temperature = SPACE_HELMET_MIN_COLD_PROTECTION_TEMPERATURE
	min_pressure_protection = 0 * ONE_ATMOSPHERE
	max_pressure_protection = 3 * ONE_ATMOSPHERE
	max_heat_protection_temperature = SPACE_SUIT_MAX_HEAT_PROTECTION_TEMPERATURE

/obj/item/clothing/suit/vrwizard
	name = "wizard robes"
	desc = "A silky robe with 0s and 1s flying off the seams."
	icon_state = "redwizard"
	armor_spec = "melee=20;bullet=20;laser=60;energy=60;bomb=70;bio=50;rad=50"
	siemens_coefficient = 0.1
	cold_protection = UPPER_TORSO | LOWER_TORSO | LEGS | FEET | ARMS | HANDS
	min_cold_protection_temperature = SPACE_SUIT_MIN_COLD_PROTECTION_TEMPERATURE
	min_pressure_protection = 0 * ONE_ATMOSPHERE
	max_pressure_protection = 3 * ONE_ATMOSPHERE
	max_heat_protection_temperature = SPACE_SUIT_MAX_HEAT_PROTECTION_TEMPERATURE

TYPE_TABLE(/obj/item/clothing/suit/vrwizard, suit_storage_spec, list(HOLD_ONLY(list(POCKET_SECURITY, POCKET_EMERGENCY, /obj/item/melee/baton,/obj/item/melee/energy/sword,/obj/item/handcuffs))))

/obj/item/clothing/head/darkvrwizard
	name = "wizard hat"
	desc = "The hat holding the most attack and defense"
	icon_state = "redwizard"
	color = "#660066"
	armor_spec = "melee=70;bullet=70;laser=40;energy=40;bomb=90;bio=70;rad=70"
	siemens_coefficient = 0.1
	cold_protection = HEAD
	min_cold_protection_temperature = SPACE_HELMET_MIN_COLD_PROTECTION_TEMPERATURE
	min_pressure_protection = 0 * ONE_ATMOSPHERE
	max_pressure_protection = 3 * ONE_ATMOSPHERE
	max_heat_protection_temperature = SPACE_SUIT_MAX_HEAT_PROTECTION_TEMPERATURE

/obj/item/clothing/suit/darkvrwizard
	name = "wizard robes"
	desc = "Robes holding the most attack and defense."
	icon_state = "psyamp"
	armor_spec = "melee=70;bullet=70;laser=40;energy=40;bomb=90;bio=70;rad=70"
	siemens_coefficient = 0.1
	cold_protection = UPPER_TORSO | LOWER_TORSO | LEGS | FEET | ARMS | HANDS
	min_cold_protection_temperature = SPACE_SUIT_MIN_COLD_PROTECTION_TEMPERATURE
	min_pressure_protection = 0 * ONE_ATMOSPHERE
	max_pressure_protection = 3 * ONE_ATMOSPHERE
	max_heat_protection_temperature = SPACE_SUIT_MAX_HEAT_PROTECTION_TEMPERATURE

//Candy section

TYPE_TABLE(/obj/item/clothing/suit/darkvrwizard, suit_storage_spec, list(HOLD_ONLY(list(POCKET_SECURITY, POCKET_EMERGENCY, /obj/item/melee/baton,/obj/item/melee/energy/sword))))
/obj/item/clothing/head/psy_crown/candycrown/get_mechanics_info(list/additional_information)
	return ..(list("It will occasionally give a momentary buff to offensive capabilities.") + additional_information)

/obj/item/clothing/head/psy_crown/candycrown
	name = "candy crown"
	desc = "A crown smelling oddly sweet"
	icon_state = "wrathcrown"
	cooldown_duration = 1 MINUTES // How long the cooldown should be.
	brainloss_cost = 0
	armor_spec = "melee=70;bullet=60;laser=50;energy=50"

/obj/item/clothing/head/psy_crown/candycrown/activate_ability(mob/living/wearer)
	..()
	wearer.apply_body_effect(/datum/body_effect/aura/candy_orange, 30 SECONDS)

/obj/item/clothing/gloves/stamina/get_mechanics_info(list/additional_information)
	return ..(list("It has a strange property of restoring hunger.") + additional_information)

/obj/item/clothing/gloves/stamina
	name = "gloves of stamina"
	desc = "A strange pair of gloves."
	icon_state = "regen"
	item_state = "graygloves"
	siemens_coefficient = 0
	armor_spec = "melee=70;bullet=60;laser=50;energy=50"

/// Worn in the gloves slot (equipped()/dropped()). With the wearer view (a field, so its automatic
/// clear when the wearer is destroyed counts too) it declares the feeding work.
/obj/item/clothing/gloves/stamina/var/worn_on_hands = FALSE
TRACKED(/obj/item/clothing/gloves/stamina, worn_on_hands)
OM_FIELD_VIEW_OF(/obj/item/clothing/gloves/stamina, wearer, CHANGE_EXPLICIT)

CAPABILITIES(/obj/item/clothing/gloves/stamina)
	every(2 SECONDS, then(PROC_REF(stamina_step)), when = nameof(worn_on_hands))

/obj/item/clothing/gloves/stamina/equipped(mob/user, slot)
	..()
	var/mob/living/carbon/human/H = wearer
	set_worn_on_hands(H && H.get_equipped_item(SLOT_ID_GLOVES) == src)
	if(worn_on_hands)
		if(H.can_feel_pain())
			to_chat(H, span_danger("You feel strange as hunger vanishes!"))
			H.custom_pain("Your hands feel strange!",1)

/obj/item/clothing/gloves/stamina/dropped(mob/user, equipping, slot)
	set_worn_on_hands(FALSE)
	var/mob/living/carbon/human/H = wearer
	if(H)
		if(H.can_feel_pain())
			to_chat(H, span_danger("You feel hungry!"))
			H.custom_pain("Your hands feel strange",1)
	..()

/// Works every 2 s while worn on the hands (the every() in its capabilities); taken off, it sleeps.
/obj/item/clothing/gloves/stamina/proc/stamina_step(datum/act/timer/A)
	var/mob/living/carbon/human/H = wearer
	if(!istype(H) || HAS_SYNTHETIC_BIOLOGY(H) || H.stat == DEAD)
		return // Robots and dead people don't have a metabolism.
	H.set_nutrition(max(H.nutrition + 8, 0))

/obj/item/clothing/suit/armor/buffvest
	name = "candy armor"
	desc = "A really strange armor made of a similar substance as the creatures near it."
	icon_state = "armor"
	blood_overlay_type = "armor"
	armor_spec = "melee=70;bullet=60;laser=50;energy=50"
	var/tension_threshold = 125
	var/cooldown = null // world.time of when this was last triggered.
	var/cooldown_duration = 3 MINUTES // How long the cooldown should be.
	var/flavor_equip = null // Message displayed to someone who puts this on their head. Drones don't get a message.
	var/flavor_unequip = null // Ditto, but for taking it off.
	var/flavor_drop = null // Ditto, but for dropping it.
	var/flavor_activate = null // Ditto, for but activating.
	var/brainloss_cost = 0

/// TRUE while worn in the suit slot by a sentient mob.
/obj/item/clothing/suit/armor/buffvest/var/worn_by_sentient = FALSE
TRACKED(/obj/item/clothing/suit/armor/buffvest, worn_by_sentient)
CAPABILITIES(/obj/item/clothing/suit/armor/buffvest)
	every(2 SECONDS, then(PROC_REF(buffvest_step)), when = nameof(worn_by_sentient))

/obj/item/clothing/suit/armor/buffvest/proc/activate_ability(mob/living/wearer)
	COOLDOWN_START(src, cooldown, cooldown_duration)
	to_chat(wearer, flavor_activate)
	to_chat(wearer, span_danger("The inside of your head hurts..."))
	wearer.injure(INJURY_NEURAL, brainloss_cost, null, src)
	wearer.apply_body_effect(/datum/body_effect/aura/candy_blue, 30 SECONDS)

/obj/item/clothing/suit/armor/buffvest/equipped(mob/living/carbon/human/H, slot)
	..()
	if(istype(H) && H.get_equipped_item(SLOT_ID_SUIT) == src && H.is_sentient())
		set_worn_by_sentient(TRUE)
		if(flavor_equip)
			to_chat(H, span_info(flavor_equip))

/obj/item/clothing/suit/armor/buffvest/dropped(mob/living/carbon/human/H, equipping, slot)
	..()
	set_worn_by_sentient(FALSE)
	if(H.is_sentient())
		if(loc == H) // Still inhand.
			if(flavor_unequip)
				to_chat(H, span_info(flavor_unequip))
		else
			if(flavor_drop)
				to_chat(H, span_info(flavor_drop))

/obj/item/clothing/suit/armor/buffvest/proc/buffvest_step(datum/act/timer/A)
	if(isliving(loc))
		var/mob/living/L = loc
		if(COOLDOWN_FINISHED(src, cooldown) && L.is_sentient() && L.get_tension() >= tension_threshold)
			activate_ability(L)

//vistor section
/obj/item/clothing/suit/armor/alien/vistor/get_mechanics_info(list/additional_information)
	return ..(list("Reduces all damage types by 25% with a 12% chance to block.") + additional_information)

/obj/item/clothing/suit/armor/alien/vistor
	name = "rocky suit"
	desc = "A strange set of armor made of rocky plates"
	icon_state = "alien_tank"
	slowdown = 0
	body_parts_covered = UPPER_TORSO|LOWER_TORSO|LEGS|ARMS
	armor_spec = "melee=25;bullet=25;laser=25;energy=25;bomb=25;bio=25;rad=25" //Should be good enough to mimic the old '12% reduction'.
	block_chance = 12

/obj/item/clothing/suit/armor/tesla/vistor
	name = "zapping suit"
	desc = "A strange set of armor crackling with lighting"
	slowdown = 0
	body_parts_covered = UPPER_TORSO|LOWER_TORSO|LEGS|ARMS
	armor_spec = "melee=60;bullet=60;laser=60;energy=60"

/obj/item/clothing/suit/armor/reactive/vistor
	name = "vibrating suit"
	desc = "A strange set of armor that crackles with energy"
	icon_state = "reactiveoff"
	slowdown = 0
	armor_spec = "melee=35;bullet=35;laser=35;energy=35"

/obj/item/clothing/suit/armor/protectionbubble
	name = "protective bubble"
	desc = "A strange set of armor that seems to coat your entire body in a thing protective bubble"
	icon_state = "armor"
	blood_overlay_type = "armor"
	armor_spec = "melee=25;bullet=25;laser=25;energy=25;bomb=50;bio=100;rad=75"
	cold_protection = UPPER_TORSO | LOWER_TORSO | LEGS | FEET | ARMS | HANDS | HEAD
	min_cold_protection_temperature = SPACE_SUIT_MIN_COLD_PROTECTION_TEMPERATURE
	min_pressure_protection = 0 * ONE_ATMOSPHERE
	max_pressure_protection = 15 * ONE_ATMOSPHERE
	max_heat_protection_temperature = SPACE_SUIT_MAX_HEAT_PROTECTION_TEMPERATURE

//scrap section which is on hold till I get foes

