/obj/item/clothing/suit/armor
	name = DEVELOPER_WARNING_NAME

	resistance_flags = FIRE_PROOF

CAPABILITIES(/obj/item/clothing/suit/armor)
	configure(item_worn(covers = CHEST, flags = THICKMATERIAL))
	configure(item_protection(cold_parts = CHEST, min_cold = ARMOR_MIN_COLD_PROTECTION_TEMPERATURE, heat_parts = CHEST, max_heat = ARMOR_MAX_HEAT_PROTECTION_TEMPERATURE, siemens = 0.6))

TYPE_TABLE(/obj/item/clothing/suit/armor, suit_storage_spec, list(HOLD_ONLY(list(POCKET_GENERIC, POCKET_EMERGENCY, POCKET_SECURITY))))

/// Suits can't go on over gloves or shoes that cover the same limbs.
TYPE_TABLE(/obj/item/clothing/suit, equip_spec, dq_spec_join(..(), list(REQ_ON(PRED_TARGET, /obj/item/clothing/suit/proc/limb_clearance, null))))

/obj/item/clothing/suit/proc/limb_clearance(mob/living/carbon/human/H)
	if(!istype(H))
		return TRUE
	for(var/obj/item/clothing/I in list(H.get_equipped_item(SLOT_ID_GLOVES), H.get_equipped_item(SLOT_ID_SHOES)))
		if(I && (worn_of(src).covers & ARMS && worn_of(I).covers & ARMS))
			return "\the [I] [I.gender == PLURAL ? "are" : "is"] in the way"
		if(I && (worn_of(src).covers & LEGS && worn_of(I).covers & LEGS))
			return "\the [I] [I.gender == PLURAL ? "are" : "is"] in the way"
	return TRUE

/obj/item/clothing/suit/armor/vest
	name = "armor"
	desc = "An armored vest that protects against some damage."
	icon_state = "armor"
	blood_overlay_type = "armor"
	armor_spec = "melee=40;bullet=30;laser=30;energy=10;bomb=10"

/obj/item/clothing/suit/armor/vest/alt
	name = "security armor"
	desc = "An armored vest that protects against some damage. This one has a NanoTrasen corporate badge."
	icon_state = "armoralt"
	item_state_slots = list(slot_r_hand_str = "armor", slot_l_hand_str = "armor")

/obj/item/clothing/suit/armor/vest/security
	name = "security armor"
	desc = "An armored vest that protects against some damage. This one has a corporate badge."
	icon_state = "armorsec"
	item_state_slots = list(slot_r_hand_str = "armor", slot_l_hand_str = "armor")

/obj/item/clothing/suit/armor/riot
	name = "riot vest"
	desc = "A vest with heavy padding to protect against melee attacks."
	icon_state = "riot"
	item_state_slots = list(slot_r_hand_str = "swat", slot_l_hand_str = "swat")
	armor_spec = "melee=80;bullet=10;laser=10;energy=10"

CAPABILITIES(/obj/item/clothing/suit/armor/riot)
	configure(item_protection(siemens = 0.5))

/obj/item/clothing/suit/armor/riot/alt
	icon_state = "riot_new"
	item_state_slots = list(slot_r_hand_str = "riot_new", slot_l_hand_str = "riot_new")

/obj/item/clothing/suit/armor/bulletproof
	name = "bullet resistant vest"
	desc = "A vest that excels in protecting the wearer against high-velocity solid projectiles."
	icon_state = "bulletproof"
	item_state_slots = list(slot_r_hand_str = "armor", slot_l_hand_str = "armor")
	blood_overlay_type = "armor"
	slowdown = 0.5
	armor_spec = "melee=10;bullet=80;laser=10;energy=10"

CAPABILITIES(/obj/item/clothing/suit/armor/bulletproof)
	configure(item_protection(siemens = 0.7))

/obj/item/clothing/suit/armor/bulletproof/alt
	icon_state = "bulletproof_new"
	item_state_slots = list(slot_r_hand_str = "bulletproof_new", slot_l_hand_str = "bulletproof_new")
	blood_overlay_type = "armor"

/obj/item/clothing/suit/armor/laserproof
	name = "ablative armor vest"
	desc = "A vest that excels in protecting the wearer against energy projectiles."
	icon_state = "armor_reflec"
	blood_overlay_type = "armor"
	slowdown = 0.5
	armor_spec = "melee=10;bullet=10;laser=80;energy=50"

CAPABILITIES(/obj/item/clothing/suit/armor/laserproof)
	configure(item_protection(siemens = 0.1))

/obj/item/clothing/suit/armor/laserproof/handle_shield(mob/user, damage, atom/damage_source = null, mob/attacker = null, def_zone = null, attack_text = "the attack")
	if(istype(damage_source, /obj/item/projectile/energy) || istype(damage_source, /obj/item/projectile/beam))
		var/obj/item/projectile/P = damage_source

		if(P.reflected) // Can't reflect twice
			return ..()

		var/reflectchance = 40 - round(damage/3)
		if(!(def_zone in list(BP_TORSO, BP_GROIN)))
			reflectchance /= 2
		if(P.starting && prob(reflectchance))
			act_message(user, null, others = span_danger("%U%'s [src.name] reflects [attack_text]!"))

			// Find a turf near or on the original location to bounce to
			var/new_x = P.starting.x + pick(0, 0, 0, 0, 0, -1, 1, -2, 2)
			var/new_y = P.starting.y + pick(0, 0, 0, 0, 0, -1, 1, -2, 2)
			var/turf/curloc = get_turf(user)

			// redirect the projectile
			P.redirect(new_x, new_y, curloc, user)
			P.reflected = 1

			return PROJECTILE_CONTINUE // complete projectile permutation

/obj/item/clothing/suit/armor/combat
	name = "combat vest"
	desc = "A vest that protects the wearer from several common types of weaponry."
	icon_state = "combat"
	blood_overlay_type = "armor"
	slowdown = 0.5
	armor_spec = "melee=50;bullet=50;laser=50;energy=30;bomb=30"

CAPABILITIES(/obj/item/clothing/suit/armor/combat)
	configure(item_protection(siemens = 0.6))

/obj/item/clothing/suit/armor/tactical
	name = "tactical armor"
	desc = "A suit of armor most often used by Special Weapons and Tactics squads. Includes padded vest with pockets along with shoulder and kneeguards."
	icon_state = "swatarmor"
	item_state_slots = list(slot_r_hand_str = "swat", slot_l_hand_str = "swat")
	slowdown = 1
	armor_spec = "melee=60;bullet=60;laser=60;energy=40;bomb=40"

CAPABILITIES(/obj/item/clothing/suit/armor/tactical)
	configure(item_worn(covers = CHEST|LEGS|ARMS, hides = HIDETIE|HIDEHOLSTER))
	configure(item_protection(siemens = 0.7))

/obj/item/clothing/suit/armor/swat
	name = "swat suit"
	desc = "A heavily armored suit that protects against moderate damage. Used in special operations."
	icon_state = "deathsquad"
	item_state_slots = list(slot_r_hand_str = "swat", slot_l_hand_str = "swat")
	slowdown = 1
	w_class = ITEMSIZE_HUGE
	armor_spec = "melee=80;bullet=60;laser=50;energy=25;bomb=50;bio=100;rad=100"

CAPABILITIES(/obj/item/clothing/suit/armor/swat)
	configure(item_worn(flags = THICKMATERIAL, covers = CHEST|LEGS|FEET|ARMS, hides = HIDEGLOVES|HIDESHOES|HIDEJUMPSUIT|HIDETIE|HIDEHOLSTER))
	configure(item_protection(gas_transfer = 0.01, permeability = 0.01, cold_parts = UPPER_TORSO | LOWER_TORSO | LEGS | FEET | ARMS | HANDS, min_cold = SPACE_SUIT_MIN_COLD_PROTECTION_TEMPERATURE, min_pressure = 0 * ONE_ATMOSPHERE, max_pressure = 20* ONE_ATMOSPHERE, siemens = 0.6))

TYPE_TABLE(/obj/item/clothing/suit/armor/swat, suit_storage_spec, list(HOLD_ONLY(list(POCKET_GENERIC, POCKET_EMERGENCY, POCKET_SECURITY))))

/obj/item/clothing/suit/armor/swat/officer
	name = "officer jacket"
	desc = "An armored jacket used in special operations."
	icon_state = "detective"
	item_state_slots = list(slot_r_hand_str = "detective", slot_l_hand_str = "detective")
	blood_overlay_type = "coat"

CAPABILITIES(/obj/item/clothing/suit/armor/swat/officer)
	configure(item_worn(hides = 0, covers = UPPER_TORSO|ARMS))

/obj/item/clothing/suit/armor/det_suit
	name = "armor"
	desc = "An armored vest with a detective's badge on it."
	icon_state = "detective-armor"
	item_state_slots = list(slot_r_hand_str = "armor", slot_l_hand_str = "armor")
	blood_overlay_type = "armor"
	armor_spec = "melee=40;bullet=30;laser=30;energy=10;bomb=10"

CAPABILITIES(/obj/item/clothing/suit/armor/det_suit)
	configure(item_worn(covers = CHEST))

// Ooold, old reactive armor.
// Alien armor has a chance to completely block attacks.
/obj/item/clothing/suit/armor/alien/get_mechanics_info(list/additional_information)
	return ..(list("It has a 20% chance to completely nullify an incoming attack, and the wearer moves slightly faster.") + additional_information)

/obj/item/clothing/suit/armor/alien
	name = "alien enhancement vest"
	desc = "It's a strange piece of what appears to be armor. It looks very light and agile. Strangely enough it seems to have been designed for a humanoid shape."
	icon_state = "alien_speed"
	blood_overlay_type = "armor"
	item_state_slots = list(slot_r_hand_str = "armor", slot_l_hand_str = "armor")
	slowdown = -1
	armor_spec = "melee=50;bullet=50;laser=50;energy=50;bomb=50;rad=40"
	var/block_chance = 20

CAPABILITIES(/obj/item/clothing/suit/armor/alien)
	configure(item_worn(covers = CHEST))
	configure(item_protection(siemens = 0.4))

/obj/item/clothing/suit/armor/alien/tank/get_mechanics_info(list/additional_information)
	return ..(list("It has a 40% chance to completely nullify an incoming attack.") + additional_information)

/obj/item/clothing/suit/armor/alien/tank
	name = "alien protection suit"
	desc = "It's really resilient yet lightweight, so it's probably meant to be armor. Strangely enough it seems to have been designed for a humanoid shape."
	icon_state = "alien_tank"
	slowdown = 0
	armor_spec = "melee=70;bullet=70;laser=70;energy=70;bomb=70;rad=40"
	block_chance = 40

CAPABILITIES(/obj/item/clothing/suit/armor/alien/tank)
	configure(item_worn(covers = CHEST|LEGS|ARMS))

/obj/item/clothing/suit/armor/alien/handle_shield(mob/user, damage, atom/damage_source = null, mob/attacker = null, def_zone = null, attack_text = "the attack")
	if(prob(block_chance))
		user.visible_message(span_danger("\The [src] completely absorbs [attack_text]!"))
		return TRUE
	return FALSE

//Non-hardsuit ERT armor.
/obj/item/clothing/suit/armor/vest/ert
	name = "emergency response team armor"
	desc = "A set of armor worn by members of the Emergency Response Team."
	icon_state = "ertarmor_cmd"
	item_state_slots = list(slot_r_hand_str = "armor", slot_l_hand_str = "armor")
	armor_spec = "melee=60;bullet=60;laser=60;energy=40;bomb=20"

CAPABILITIES(/obj/item/clothing/suit/armor/vest/ert)
	configure(item_worn(covers = CHEST|ARMS))

//Commander
/obj/item/clothing/suit/armor/vest/ert/command
	name = "emergency response team commander armor"
	desc = "A set of armor worn by the commander of an Emergency Response Team. Has blue highlights."

//Security
/obj/item/clothing/suit/armor/vest/ert/security
	name = "emergency response team security armor"
	desc = "A set of armor worn by security members of the Emergency Response Team. Has red highlights."
	icon_state = "ertarmor_sec"

//Engineer
/obj/item/clothing/suit/armor/vest/ert/engineer
	name = "emergency response team engineer armor"
	desc = "A set of armor worn by engineering members of the Emergency Response Team. Has orange highlights."
	icon_state = "ertarmor_eng"

//Medical
/obj/item/clothing/suit/armor/vest/ert/medical
	name = "emergency response team medical armor"
	desc = "A set of armor worn by medical members of the Emergency Response Team. Has blue and white highlights."
	icon_state = "ertarmor_med"

//New Vests
/obj/item/clothing/suit/storage/vest
	name = "armor vest"
	desc = "A simple kevlar plate carrier."
	icon_state = "kvest"
	blood_overlay_type = "armor"
	item_state_slots = list(slot_r_hand_str = "armor", slot_l_hand_str = "armor")
	armor_spec = "melee=40;bullet=30;laser=30;energy=10;bomb=10"



TYPE_TABLE(/obj/item/clothing/suit/storage/vest, suit_storage_spec, list(HOLD_ONLY(list(POCKET_GENERIC, POCKET_EMERGENCY, POCKET_SECURITY))))

/obj/item/clothing/suit/storage/vest/officer
	name = "officer armor vest"
	desc = "A simple kevlar plate carrier. This one has a security holobadge clipped to the chest."
	icon_state = "officervest_nobadge"
	item_state_slots = list(slot_r_hand_str = "armor", slot_l_hand_str = "armor")
	icon_badge = "officervest_badge"
	icon_nobadge = "officervest_nobadge"

/obj/item/clothing/suit/storage/vest/aces
	name = "ACE security rig"
	desc = "A set of lightweight armor designed to be worn over the matching ACE security undersuit. Includes thigh, shin, and forearm protectors in addition to standard torso and groin guards."
	icon_state = "aces_armor"
	item_state_slots = list(slot_r_hand_str = "armor", slot_l_hand_str = "armor")

CAPABILITIES(/obj/item/clothing/suit/storage/vest/aces)
	configure(item_worn(covers = CHEST|LEGS|ARMS))

/obj/item/clothing/suit/storage/vest/warden
	name = "warden armor vest"
	desc = "A simple kevlar plate carrier. This one has a silver badge clipped to the chest."
	icon_state = "wardenvest_nobadge"
	item_state_slots = list(slot_r_hand_str = "armor", slot_l_hand_str = "armor")
	icon_badge = "wardenvest_badge"
	icon_nobadge = "wardenvest_nobadge"

/obj/item/clothing/suit/storage/vest/wardencoat
	name = JOB_WARDEN + "'s jacket"
	desc = "An armoured jacket with silver rank pips and livery."
	icon_state = "warden_jacket"
	blood_overlay_type = "suit"

CAPABILITIES(/obj/item/clothing/suit/storage/vest/wardencoat)
	configure(item_worn(covers = CHEST|ARMS|LEGS, hides = HIDETIE|HIDEHOLSTER))

/obj/item/clothing/suit/storage/vest/wardencoat/alt
	name = JOB_WARDEN + "'s jacket"
	desc = "An armoured jacket with silver rank pips and livery."
	icon_state = "warden_alt"

CAPABILITIES(/obj/item/clothing/suit/storage/vest/wardencoat/alt)
	configure(item_worn(covers = CHEST|ARMS|LEGS))

/obj/item/clothing/suit/storage/vest/hos
	name = "head of security armor vest"
	desc = "A simple kevlar plate carrier. This one has a gold badge clipped to the chest."
	icon_state = "hosvest_nobadge"
	item_state_slots = list(slot_r_hand_str = "armor", slot_l_hand_str = "armor")
	icon_badge = "hosvest_badge"
	icon_nobadge = "hosvest_nobadge"

/obj/item/clothing/suit/storage/vest/hoscoat
	name = "armored coat"
	desc = "A greatcoat enhanced with a special alloy for some protection and style."
	icon_state = "hos"
	blood_overlay_type = "suit"

CAPABILITIES(/obj/item/clothing/suit/storage/vest/hoscoat)
	configure(item_worn(covers = CHEST|ARMS|LEGS, hides = HIDETIE|HIDEHOLSTER))

//Jensen cosplay gear
/obj/item/clothing/suit/storage/vest/hoscoat/jensen
	name = "armored trenchcoat"
	desc = "A trenchcoat augmented with a special alloy for some protection and style."
	icon_state = "hostrench"

CAPABILITIES(/obj/item/clothing/suit/storage/vest/hoscoat/jensen)
	configure(item_worn(hides = HIDEHOLSTER))

/obj/item/clothing/suit/storage/vest/pcrc
	name = "PCRC armor vest"
	desc = "A simple kevlar plate carrier belonging to Proxima Centauri Risk Control. This one has a PCRC crest clipped to the chest."
	icon_state = "pcrcvest_nobadge"
	item_state_slots = list(slot_r_hand_str = "armor", slot_l_hand_str = "armor")
	icon_badge = "pcrcvest_badge"
	icon_nobadge = "pcrcvest_nobadge"

/obj/item/clothing/suit/storage/vest/solgov/hedberg
	name = "Hedberg-Hammarstrom armor vest"
	desc = "A simple kevlar plate carrier belonging to Hedberg-Hammarstrom. The company logo is clearly visible."
	icon_state = "secwebvest"

/obj/item/clothing/suit/storage/vest/solgov
	icon_state = "solvest"
	armor_spec = "melee=40;bullet=40;laser=40;energy=25;bomb=30"

/obj/item/clothing/suit/storage/vest/solgov/heavy
	icon_state = "solwebvest"

/obj/item/clothing/suit/storage/vest/solgov/command
	icon_state = "comwebvest"

/obj/item/clothing/suit/storage/vest/tactical //crack at a more balanced mid-range armor, minor improvements over standard vests, with the idea "modern" combat armor would focus on energy weapon protection.
	name = "tactical armored vest"
	desc = "A heavy armored vest in a fetching tan. It is surprisingly flexible and light, even with the extra webbing and advanced ceramic plates."
	icon_state = "tacwebvest"
	item_state = "tacwebvest"
	armor_spec = "melee=40;bullet=40;laser=60;energy=35;bomb=30"

/obj/item/clothing/suit/storage/vest/heavy/flexitac //a reskin of the above to have a matching armor set
	name = "tactical light vest"
	desc = "An armored vest made from advanced flexible ceramic plates. It's surprisingly mobile, if a little unfashionable."
	icon_state = "flexitac"
	item_state = "flexitac"
	armor_spec = "melee=40;bullet=40;laser=60;energy=35;bomb=30"
	slowdown = 0.5

CAPABILITIES(/obj/item/clothing/suit/storage/vest/heavy/flexitac)
	configure(item_protection(cold_parts = CHEST, min_cold = T0C - 20))

/obj/item/clothing/suit/storage/vest/detective
	name = "detective armor vest"
	desc = "A simple kevlar plate carrier in a vintage brown, it has a badge clipped to the chest that reads, 'Private investigator'."
	icon_state = "detectivevest_nobadge"
	item_state_slots = list(slot_r_hand_str = "armor", slot_l_hand_str = "armor")
	icon_badge = "detectivevest_badge"
	icon_nobadge = "detectivevest_nobadge"

/obj/item/clothing/suit/storage/vest/press
	name = "press vest"
	icon_state = "pvest"
	desc = "A simple kevlar plate carrier. This one has the word 'Press' embroidered on patches on the back and front."
	item_state_slots = list(slot_r_hand_str = "armor", slot_l_hand_str = "armor")

TYPE_TABLE(/obj/item/clothing/suit/storage/vest/press, suit_storage_spec, list(HOLD_ONLY(list(POCKET_GENERIC, POCKET_EMERGENCY, POCKET_DETECTIVE, /obj/item/camera,/obj/item/clothing/head/helmet))))

/obj/item/clothing/suit/storage/vest/heavy
	name = "heavy armor vest"
	desc = "A heavy kevlar plate carrier with webbing attached."
	icon_state = "webvest"
	item_state_slots = list(slot_r_hand_str = "swat", slot_l_hand_str = "swat")
	armor_spec = "melee=50;bullet=40;laser=40;energy=25;bomb=25"
	slowdown = 0.5

/obj/item/clothing/suit/storage/vest/heavy/officer
	name = "officer heavy armor vest"
	desc = "A heavy kevlar plate carrier with webbing attached. This one has a security holobadge clipped to the chest."
	icon_state = "officerwebvest_nobadge"
	item_state_slots = list(slot_r_hand_str = "swat", slot_l_hand_str = "swat")
	icon_badge = "officerwebvest_badge"
	icon_nobadge = "officerwebvest_nobadge"

/obj/item/clothing/suit/storage/vest/heavy/warden
	name = "warden heavy armor vest"
	desc = "A heavy kevlar plate carrier with webbing attached. This one has a silver badge clipped to the chest."
	icon_state = "wardenwebvest_nobadge"
	item_state_slots = list(slot_r_hand_str = "swat", slot_l_hand_str = "swat")
	icon_badge = "wardenwebvest_badge"
	icon_nobadge = "wardenwebvest_nobadge"

/obj/item/clothing/suit/storage/vest/heavy/hos
	name = "head of security heavy armor vest"
	desc = "A heavy kevlar plate carrier with webbing attached. This one has a gold badge clipped to the chest."
	icon_state = "hoswebvest_nobadge"
	item_state_slots = list(slot_r_hand_str = "swat", slot_l_hand_str = "swat")
	icon_badge = "hoswebvest_badge"
	icon_nobadge = "hoswebvest_nobadge"

/obj/item/clothing/suit/storage/vest/heavy/pcrc
	name = "PCRC heavy armor vest"
	desc = "A heavy kevlar plate carrier belonging to Proxima Centauri Risk Control with webbing attached. This one has a PCRC crest clipped to the chest."
	icon_state = "pcrcwebvest_nobadge"
	item_state_slots = list(slot_r_hand_str = "swat", slot_l_hand_str = "swat")
	icon_badge = "pcrcwebvest_badge"
	icon_nobadge = "pcrcwebvest_nobadge"

//Provides the protection of a merc voidsuit, but only covers the chest/groin, and also takes up a suit slot. In exchange it has no slowdown and provides storage.
/obj/item/clothing/suit/storage/vest/heavy/merc
	name = "heavy armor vest"
	desc = "A high-quality heavy kevlar plate carrier in a fetching tan. The vest is surprisingly flexible, and possibly made of an advanced material."
	icon_state = "mercwebvest"
	item_state_slots = list(slot_r_hand_str = "swat", slot_l_hand_str = "swat")
	armor_spec = "melee=60;bullet=60;laser=60;energy=40;bomb=40"
	slowdown = 0

//All of the armor below is mostly unused

/obj/item/clothing/suit/armor/centcomm
	name = "CentCom armor"
	desc = "A suit that protects against some damage."
	icon_state = "centcom"
	item_state_slots = list(slot_r_hand_str = "armor", slot_l_hand_str = "armor")
	w_class = ITEMSIZE_LARGE//bulky item

CAPABILITIES(/obj/item/clothing/suit/armor/centcomm)
	configure(item_worn(covers = CHEST|LEGS|FEET|ARMS|HANDS, hides = HIDEGLOVES|HIDESHOES|HIDEJUMPSUIT|HIDETIE|HIDEHOLSTER))
	configure(item_protection(cold_parts = UPPER_TORSO | LOWER_TORSO | LEGS | FEET | ARMS | HANDS, min_cold = SPACE_SUIT_MIN_COLD_PROTECTION_TEMPERATURE, siemens = 0))

TYPE_TABLE(/obj/item/clothing/suit/armor/centcomm, suit_storage_spec, list(HOLD_ONLY(list(POCKET_GENERIC, POCKET_EMERGENCY, POCKET_SECURITY))))

/obj/item/clothing/suit/armor/heavy
	name = "heavy armor"
	desc = "An old military-grade suit of armor. Incredibly robust against brute force damage! However, it offers little protection from energy-based weapons, which, combined with its bulk, makes it woefully obsolete."
	icon_state = "heavy"
	item_state_slots = list(slot_r_hand_str = "swat", slot_l_hand_str = "swat")
	armor_spec = "melee=90;bullet=80;laser=10;energy=10;bomb=80"
	w_class = ITEMSIZE_HUGE // Very bulky, very heavy.
	slowdown = 5 // If you're a tank you're gonna move like a tank.

CAPABILITIES(/obj/item/clothing/suit/armor/heavy)
	configure(item_worn(covers = CHEST|LEGS|FEET|ARMS|HANDS, hides = HIDEGLOVES|HIDESHOES|HIDEJUMPSUIT|HIDETIE|HIDEHOLSTER))
	configure(item_protection(gas_transfer = 0.90, siemens = 0))

/obj/item/clothing/suit/armor/tdome
	name = DEVELOPER_WARNING_NAME
	armor_spec = "melee=60;bullet=60;laser=60;energy=40;bomb=40"

CAPABILITIES(/obj/item/clothing/suit/armor/tdome)
	configure(item_worn(covers = CHEST|LEGS|FEET|ARMS|HANDS, hides = HIDEGLOVES|HIDESHOES|HIDEJUMPSUIT))

/obj/item/clothing/suit/armor/tdome/red
	name = "Thunderdome suit (red)"
	desc = "Reddish armor."
	icon_state = "tdred"

CAPABILITIES(/obj/item/clothing/suit/armor/tdome/red)
	configure(item_protection(siemens = 1))

/obj/item/clothing/suit/armor/tdome/green
	name = "Thunderdome suit (green)"
	desc = "Pukish armor."
	icon_state = "tdgreen"

CAPABILITIES(/obj/item/clothing/suit/armor/tdome/green)
	configure(item_protection(siemens = 1))

//Modular plate carriers
/obj/item/clothing/suit/armor/pcarrier
	name = "plate carrier"
	desc = "A lightweight black plate carrier vest. It can be equipped with armor plates, but provides no protection of its own."
	icon = 'icons/obj/clothing/modular_armor.dmi'
	item_icons = list(slot_wear_suit_str = 'icons/mob/modular_armor.dmi')
	icon_state = "pcarrier"
	valid_accessory_slots = (\
		ACCESSORY_SLOT_INSIGNIA\
		|ACCESSORY_SLOT_ARMOR_C\
		|ACCESSORY_SLOT_ARMOR_A\
		|ACCESSORY_SLOT_ARMOR_L\
		|ACCESSORY_SLOT_ARMOR_S\
		|ACCESSORY_SLOT_ARMOR_M\
		|ACCESSORY_SLOT_OVER\
		|ACCESSORY_SLOT_ARMBAND) // let pcarriers have fashion
	restricted_accessory_slots = (\
		ACCESSORY_SLOT_INSIGNIA\
		|ACCESSORY_SLOT_ARMOR_C\
		|ACCESSORY_SLOT_ARMOR_A\
		|ACCESSORY_SLOT_ARMOR_L\
		|ACCESSORY_SLOT_ARMOR_S\
		|ACCESSORY_SLOT_ARMOR_M\
		|ACCESSORY_SLOT_ARMBAND) // let pcarriers have fashion
	blood_overlay_type = "armor"

TYPE_TABLE(/obj/item/clothing/suit/armor/pcarrier, equip_spec, dq_spec_join(..(), list(REQ_ON(PRED_TARGET, /obj/item/clothing/suit/armor/pcarrier/proc/plate_clearance, null))))

/obj/item/clothing/suit/armor/pcarrier/proc/plate_clearance(mob/living/carbon/human/H)
	if(!istype(H))
		return TRUE
	if(H.get_equipped_item(SLOT_ID_GLOVES) && (worn_of(H.get_equipped_item(SLOT_ID_GLOVES)).covers & ARMS))
		for(var/obj/item/clothing/accessory/A in contents_of(src))
			if(worn_of(A).covers & ARMS)
				return "\the [A] and \the [H.get_equipped_item(SLOT_ID_GLOVES)] are in each other's way"
	if(H.get_equipped_item(SLOT_ID_SHOES) && (worn_of(H.get_equipped_item(SLOT_ID_SHOES)).covers & LEGS))
		for(var/obj/item/clothing/accessory/A in contents_of(src))
			if(worn_of(A).covers & LEGS)
				return "\the [A] and \the [H.get_equipped_item(SLOT_ID_SHOES)] are in each other's way"
	return TRUE

/obj/item/clothing/suit/armor/pcarrier/explorer
	name = "explorer plate carrier" // Clarity for vendors.
	desc = "A lightweight explorer plate carrier. It can be equipped with armor plates, but only protects from the cold on it's own."
	icon_state = "explorer"
	flags = THICKMATERIAL

CAPABILITIES(/obj/item/clothing/suit/armor/pcarrier/explorer)
	configure(item_protection(min_cold = SPACE_SUIT_MIN_COLD_PROTECTION_TEMPERATURE, cold_parts = CHEST|LEGS|ARMS))

/obj/item/clothing/suit/armor/pcarrier/light
	starting_accessories = list(/obj/item/clothing/accessory/armor/armorplate)

/obj/item/clothing/suit/armor/pcarrier/light/sol
	starting_accessories = list(/obj/item/clothing/accessory/armor/armorplate, /obj/item/clothing/accessory/armor/tag)

/obj/item/clothing/suit/armor/pcarrier/light/nt
	starting_accessories = list(/obj/item/clothing/accessory/armor/armorplate, /obj/item/clothing/accessory/armor/tag/nt)

/obj/item/clothing/suit/armor/pcarrier/medium
	starting_accessories = list(/obj/item/clothing/accessory/armor/armorplate/medium, /obj/item/clothing/accessory/storage/pouches)

/obj/item/clothing/suit/armor/pcarrier/medium/sol
	starting_accessories = list(/obj/item/clothing/accessory/armor/armorplate/medium, /obj/item/clothing/accessory/storage/pouches, /obj/item/clothing/accessory/armor/tag)

/obj/item/clothing/suit/armor/pcarrier/medium/security
	starting_accessories = list(/obj/item/clothing/accessory/armor/armorplate/medium, /obj/item/clothing/accessory/storage/pouches, /obj/item/clothing/accessory/armor/tag/sec)

/obj/item/clothing/suit/armor/pcarrier/medium/command
	starting_accessories = list(/obj/item/clothing/accessory/armor/armorplate/medium, /obj/item/clothing/accessory/storage/pouches, /obj/item/clothing/accessory/armor/tag/com)

/obj/item/clothing/suit/armor/pcarrier/medium/nt
	starting_accessories = list(/obj/item/clothing/accessory/armor/armorplate/medium, /obj/item/clothing/accessory/storage/pouches, /obj/item/clothing/accessory/armor/tag/nt)

/obj/item/clothing/suit/armor/pcarrier/blue
	name = "blue plate carrier"
	desc = "A lightweight blue plate carrier vest. It can be equipped with armor plates, but provides no protection of its own."
	icon_state = "pcarrier_blue"

/obj/item/clothing/suit/armor/pcarrier/press
	name = "light blue plate carrier"
	desc = "A lightweight light blue plate carrier vest. It can be equipped with armor plates, but provides no protection of its own."
	icon_state = "pcarrier_press"

/obj/item/clothing/suit/armor/pcarrier/blue/sol
	name = "peacekeeper plate carrier"
	desc = "A lightweight plate carrier vest in SCG Peacekeeper colors. It can be equipped with armor plates, but provides no protection of its own."
	starting_accessories = list(/obj/item/clothing/accessory/armor/armorplate/medium, /obj/item/clothing/accessory/storage/pouches/blue, /obj/item/clothing/accessory/armor/armguards/blue, /obj/item/clothing/accessory/armor/tag)

/obj/item/clothing/suit/armor/pcarrier/green
	name = "green plate carrier"
	desc = "A lightweight green plate carrier vest. It can be equipped with armor plates, but provides no protection of its own."
	icon_state = "pcarrier_green"

/obj/item/clothing/suit/armor/pcarrier/navy
	name = "navy plate carrier"
	desc = "A lightweight navy blue plate carrier vest. It can be equipped with armor plates, but provides no protection of its own."
	icon_state = "pcarrier_navy"

/obj/item/clothing/suit/armor/pcarrier/tan
	name = "tan plate carrier"
	desc = "A lightweight tan plate carrier vest. It can be equipped with armor plates, but provides no protection of its own."
	icon_state = "pcarrier_tan"

/obj/item/clothing/suit/armor/pcarrier/laserproof
	name = "ablative plate carrier"
	desc = "A specialist laser resistant plate carrier. It can be equipped with armour plates, but provides very little protection of its own."
	icon_state = "ablative"
	armor_spec = "laser=5;energy=5"
	starting_accessories = list(/obj/item/clothing/accessory/armor/armorplate/laserproof)

/obj/item/clothing/suit/armor/pcarrier/bulletproof
	name = "ballistic plate carrier"
	desc = "A specialist bullet resistant plate carrier. It can be equipped with armour plates, but provides very little protection of its own."
	icon_state = "ballistic"
	armor_spec = "bullet=5;bomb=5"
	starting_accessories = list(/obj/item/clothing/accessory/armor/armorplate/bulletproof)

/obj/item/clothing/suit/armor/pcarrier/riot
	name = "riot plate carrier"
	desc = "A specialist melee resistant plate carrier. It can be equipped with armour plates, but provides very little protection of its own."
	icon_state = "riot"
	armor_spec = "melee=5"
	starting_accessories = list(/obj/item/clothing/accessory/armor/armorplate/riot)

/obj/item/clothing/suit/armor/pcarrier/explorer/light
	starting_accessories = list(/obj/item/clothing/accessory/armor/armorplate/explorer, /obj/item/clothing/accessory/armor/armguards/explorer, /obj/item/clothing/accessory/armor/legguards/explorer, /obj/item/clothing/accessory/storage/pouches/green)

/obj/item/clothing/suit/armor/pcarrier/tan/tactical
	name = "tactical plate carrier"
	starting_accessories = list(/obj/item/clothing/accessory/armor/armorplate/tactical, /obj/item/clothing/accessory/storage/pouches/large/tan)

/obj/item/clothing/suit/armor/pcarrier/merc
	starting_accessories = list(/obj/item/clothing/accessory/armor/armorplate/merc, /obj/item/clothing/accessory/armor/armguards/merc, /obj/item/clothing/accessory/armor/legguards/merc, /obj/item/clothing/accessory/storage/pouches/large)

/obj/item/clothing/suit/armor/pcarrier/laserproof/full
	starting_accessories = list(/obj/item/clothing/accessory/armor/armorplate/laserproof, /obj/item/clothing/accessory/armor/armguards/laserproof, /obj/item/clothing/accessory/armor/legguards/laserproof, /obj/item/clothing/accessory/storage/pouches/blue)

/obj/item/clothing/suit/armor/pcarrier/bulletproof/full
	starting_accessories = list(/obj/item/clothing/accessory/armor/armorplate/bulletproof, /obj/item/clothing/accessory/armor/armguards/bulletproof, /obj/item/clothing/accessory/armor/legguards/bulletproof, /obj/item/clothing/accessory/storage/pouches)

/obj/item/clothing/suit/armor/pcarrier/riot/full
	starting_accessories = list(/obj/item/clothing/accessory/armor/armorplate/riot, /obj/item/clothing/accessory/armor/armguards/riot, /obj/item/clothing/accessory/armor/legguards/riot, /obj/item/clothing/accessory/storage/pouches)

/obj/item/clothing/suit/armor/vest/wolftaur
	name = "wolf-taur armor vest"
	desc = "An armored vest that protects against some damage. It appears to be created for a wolf-taur."
	icon = 'icons/mob/taursuits_wolf.dmi'
	icon_state = "wolf_item"
	item_state = "heavy_wolf_armor"

TYPE_TABLE(/obj/item/clothing/suit/armor/vest/wolftaur, fit_spec, null)

TYPE_TABLE(/obj/item/clothing/suit/armor/vest/wolftaur, equip_spec, dq_spec_join(..(), list(REQ_ON(PRED_TARGET, /obj/item/clothing/suit/armor/vest/wolftaur/proc/taur_fit, "you need a wolf-taur half to wear this"))))

/obj/item/clothing/suit/armor/vest/wolftaur/proc/taur_fit(mob/living/carbon/human/H)
	return istype(H) && istype(H.tail_style, /datum/sprite_accessory/tail/taur/wolf)

// HoS armor improved by to be slightly better than normal security stuff.
/obj/item/clothing/suit/storage/vest/hoscoat
	armor_spec = "melee=50;bullet=40;laser=40;energy=25;bomb=25"

/obj/item/clothing/suit/storage/vest/hos
	armor_spec = "melee=50;bullet=40;laser=40;energy=25;bomb=25"

// Override Polaris's "confederate" naming convention. I hate it.
/obj/item/clothing/suit/storage/vest/solgov
	name = "\improper Solar Central Government" // SolGov
	desc = "A synthetic armor vest. This one is marked with the crest of the Society of Universal CartographersSolar Central Government." // Terran Commonwealth to Solar Central Government

/obj/item/clothing/suit/storage/vest/solgov/heavy
	name = "\improper Solar Central Government heavy armored vest" // SolGov
	desc = "A synthetic armor vest with SECURITY printed in distinctive blue lettering on the chest. This one has added webbing and ballistic plates." // Old comment: USDF does peacekeeping, not these guys.

/obj/item/clothing/suit/storage/vest/solgov/security
	name = "master at arms heavy armored vest"
	desc = "A synthetic armor vest with MASTER AT ARMS printed in silver lettering on the chest. This one has added webbing and ballistic plates."

/obj/item/clothing/suit/storage/vest/solgov/command
	name = "commander heavy armored vest"
	desc = "A synthetic armor vest with Solar Central Government printed in detailed gold lettering on the chest. This one has added webbing and ballistic plates." // SolGov

/obj/item/clothing/suit/armor/combat/USDF
	name = "marine body armor"
	desc = "When I joined the Corps, we didn't have any fancy-schmanzy armor. We had sticks! Two sticks, and a rock for the whole platoon-and we had to <i>share</i> the rock!"
	icon_state = "unsc_armor"

CAPABILITIES(/obj/item/clothing/suit/armor/combat/USDF)
	configure(item_worn(covers = CHEST))

/obj/item/clothing/suit/armor/combat/imperial
	name = "imperial soldier armor"
	desc = "Made out of an especially light metal, it lets you conquer in style."
	icon_state = "ge_armor"

CAPABILITIES(/obj/item/clothing/suit/armor/combat/imperial)
	configure(item_worn(covers = CHEST))

/obj/item/clothing/suit/armor/combat/imperial/centurion
	name = "imperial centurion armor"
	desc = "Not all heroes wear capes, but it'd be cooler if they did."
	icon_state = "ge_armorcent"

/obj/item/clothing/suit/storage/vest/wardencoat/alt2
	icon_state = "warden_jacket_old"

/obj/item/clothing/suit/storage/vest/hoscoat/jensen/alt
	icon_state = "hostrench_old"

// Armor Versions Here
/obj/item/clothing/suit/armor/combat/crusader
	name = "crusader armor"
	desc = "ye olde knight, risen again."
	icon_state = "crusader"
	icon = 'icons/obj/clothing/knights_vr.dmi'
	icon_override = 'icons/obj/clothing/knights_vr.dmi'
	armor_spec = "melee=80;bullet=50;laser=10"

CAPABILITIES(/obj/item/clothing/suit/armor/combat/crusader)
	configure(item_worn(covers = CHEST))
	configure(item_protection(siemens = 2))

/obj/item/clothing/suit/armor/combat/crusader/bedevere
	name = "bedevere's armor"
	desc = "ye olde knight, risen again."
	icon_state = "bedevere"

CAPABILITIES(/obj/item/clothing/suit/armor/combat/crusader/bedevere)
	configure(item_worn(covers = CHEST))

/obj/item/clothing/suit/armor/combat/crusader/quizzler
	name = "knight's armor"
	desc = "ye olde knight, risen again."
	icon_state = "quizzler"
	armor_spec = "melee=60;bullet=10;laser=10"

/obj/item/clothing/suit/armor/combat/crusader/pink
	name = "knight's armor"
	desc = "ye olde knight, risen again."
	icon_state = "pink"
	armor_spec = "melee=60;bullet=10;laser=10"

// Costume Versions Here
/obj/item/clothing/suit/armor/combat/crusader_costume
	name = "crusader costume armor"
	desc = "ye olde knight, risen again."
	icon_state = "crusader"
	icon = 'icons/obj/clothing/knights_vr.dmi'
	icon_override = 'icons/obj/clothing/knights_vr.dmi'
	armor_spec = ""

CAPABILITIES(/obj/item/clothing/suit/armor/combat/crusader_costume)
	configure(item_worn(covers = CHEST))
	configure(item_protection(siemens = 1))

/obj/item/clothing/suit/armor/combat/crusader_costume/bedevere
	name = "bedevere's costume armor"
	desc = "ye olde knight, risen again."
	icon_state = "bedevere"

CAPABILITIES(/obj/item/clothing/suit/armor/combat/crusader_costume/bedevere)
	configure(item_worn(covers = CHEST))

//Deluxe explorer suit
/obj/item/clothing/suit/armor/pcarrier/explorer/deluxe
	name = "modular explorer suit"
	desc = "A modification of the explorer suit with a modular armor system. Requires you to insert armor plates."

// 'Crusader' armor
/obj/item/clothing/suit/armor/crusader
	name = "crusader armor"
	desc = "God will protect those who defend his faith."
	armor_spec = "melee=50;bullet=50;laser=50;energy=25;bomb=30"
	icon_state = "crusader_suit"

/obj/item/clothing/head/helmet/crusader
	name = "crusader helmet"
	desc = "God will protect those who defend his faith."
	armor_spec = "melee=50;bullet=50;laser=50;energy=25;bomb=30"
	icon_state = "crusader_head"

/obj/item/clothing/suit/armor/combat/crusader_explo
	name = "explorer low tech suit"
	desc = "A low tech armoured suit for exploring harsh environments."
	icon_state = "crusader_explo"
	icon = 'icons/obj/clothing/knights_vr.dmi'
	icon_override = 'icons/obj/clothing/knights_vr.dmi'
	flags = THICKMATERIAL
	slowdown=0
	armor_spec = "melee=30;bullet=20;laser=20;energy=20;bomb=35;bio=75;rad=35" // Inferior to sec vests in bullet/laser but better for environmental protection.

CAPABILITIES(/obj/item/clothing/suit/armor/combat/crusader_explo)
	configure(item_worn(covers = CHEST|LEGS|ARMS))
	configure(item_protection(min_cold = SPACE_SUIT_MIN_COLD_PROTECTION_TEMPERATURE, cold_parts = CHEST|LEGS|ARMS, siemens = 0.9))

TYPE_TABLE(/obj/item/clothing/suit/armor/combat/crusader_explo, suit_storage_spec, list(HOLD_ONLY(list(POCKET_GENERIC, POCKET_EMERGENCY, POCKET_EXPLO, POCKET_ALL_TANKS, POCKET_MINING))))

/obj/item/clothing/suit/armor/combat/crusader_explo/FM
	name = "field medic low tech suit"
	icon_state = "crusader_explo/FM"

// martian miner coat
/obj/item/clothing/suit/storage/vest/martian_miner
	name = "martian miner's coat"
	desc = "A sturdy, rugged coat once favoured by miners on Mars. These coats became strongly associated with early Martian Independence movements as a result, and so remain moderately popular amongst members of the Third Ares Confederation to this day."
	icon_state = "martian_miner"

/obj/item/clothing/suit/storage/vest/martian_miner/reinforced
	name = "reinforced martian miner's coat"
	desc = "A sturdy, rugged coat once favoured by miners on Mars. These coats became strongly associated with early Martian Independence movements as a result, and so remain moderately popular amongst members of the Third Ares Confederation to this day. This one appears to have been discreetly lined with a hardened polymesh substrate, rendering it more resilient to physical damage."
	armor_spec = "melee=25;bullet=15;laser=15;bomb=25"

/obj/item/clothing/suit/storage/vest/officer
	sprite_sheets = list(
		SPECIES_TESHARI = 'icons/inventory/suit/mob_teshari.dmi',
		SPECIES_VOX = 'icons/inventory/suit/mob_vox.dmi'
		)
/obj/item/clothing/suit/armor/pcarrier/primative
	name = "makeshift suit"
	desc = "A lightweight makeshift plate carrier vest"
	slowdown = 0.5
	icon_state = "explorer"
	flags = THICKMATERIAL

CAPABILITIES(/obj/item/clothing/suit/armor/pcarrier/primative)
	configure(item_protection(min_cold = SPACE_SUIT_MIN_COLD_PROTECTION_TEMPERATURE, cold_parts = UPPER_TORSO|LOWER_TORSO|LEGS|ARMS))

/obj/item/clothing/suit/storage/vest/martian_miner/unarmored
	armor_spec = "bomb=25"

/obj/item/clothing/suit/storage/vest/viper_suit // Still WIP but functional.
	name = "viper combat suit"
	desc = "A suit of armor designed for naga-appearing creatures. Offers modest protection for its light weight."
	slowdown = 0.2
	icon = 'icons/mob/viper_suit_ch.dmi'
	icon_override = 'icons/mob/viper_suit_ch.dmi'
	icon_state = "viper_suit"
	armor_spec = "melee=35;bullet=35;laser=35;energy=35;bomb=25;bio=20;rad=20"

CAPABILITIES(/obj/item/clothing/suit/storage/vest/viper_suit)
	configure(item_worn(covers = HEAD|UPPER_TORSO|LOWER_TORSO|LEGS|FEET|ARMS|HANDS))

/obj/item/clothing/suit/armor/yw/blueshield
	name = "Blue Shield Security Armor"
	desc = "An armored vest with the badge of a Blueshield Lieutenant."
	icon = 'icons/mob/suit_yw.dmi'
	icon_state = "blueshield"
	icon_override = 'icons/mob/suit_yw.dmi'
	item_state = "blueshield_s"
	blood_overlay_type = "armor"
	armor_spec = "melee=40;bullet=30;laser=30;energy=10;bomb=10"

/obj/item/clothing/suit/storage/toggle/yw/secjacket
	name = "security jacket"
	desc = "A sturdy black jacket with reinforced fabric. Bears insignia of NT corporate security."
	icon = 'icons/mob/suit_yw.dmi'
	icon_state = "secjacket_open"
	icon_override = 'icons/mob/suit_yw.dmi'
	item_state = "secjacket_open_s"
	armor_spec = "melee=15;bullet=10;laser=15;energy=5;bomb=15"
	open = 1

CAPABILITIES(/obj/item/clothing/suit/storage/toggle/yw/secjacket)
	configure(item_worn(covers = UPPER_TORSO|LOWER_TORSO|ARMS, hides = HIDEHOLSTER))
	configure(item_protection(cold_parts = UPPER_TORSO|LOWER_TORSO|ARMS, heat_parts = UPPER_TORSO|LOWER_TORSO|ARMS))

/// Overrides the "Toggle Coat Buttons" interaction (storage.dm).
/obj/item/clothing/suit/storage/toggle/yw/secjacket/toggle_toggle_verb(datum/act/op/A)
	var/mob/user = A.actor
	if(!user.canmove || user.stat || user.restrained())
		return 0

	if(open == 1) //Will check whether icon state is currently set to the "open" or "closed" state and switch it around with a message to the user
		open = 0
		set_icon_state("secjacket")
		set_item_state("secjacket_s")
		set_flags_inv(HIDETIE|HIDEHOLSTER)
		to_chat(user, "You button up the coat.")
	else if(open == 0)
		open = 1
		set_icon_state("secjacket_open")
		set_item_state("secjacket_open_s")
		set_flags_inv(HIDEHOLSTER)
		to_chat(user, "You unbutton the coat.")
	else //in case some goofy admin switches icon states around without switching the icon_open or icon_closed
		to_chat(user, "You attempt to button-up the velcro on your [src], before promptly realising how silly you are.")
		return

/obj/item/clothing/suit/armor/yw/blueshieldcoat
	name = "Blue Shield Security Coat"
	desc = "NT deluxe ripoff. You finally have your own coat."
	icon = 'icons/mob/suit_yw.dmi'
	icon_state = "blueshieldcoat"
	icon_override = 'icons/mob/suit_yw.dmi'
	item_state = "blueshieldcoat_s"
	blood_overlay_type = "armor"
	armor_spec = "melee=20;bullet=15;laser=15;energy=10;bomb=10"

CAPABILITIES(/obj/item/clothing/suit/armor/yw/blueshieldcoat)
	configure(item_protection(cold_parts = UPPER_TORSO|LOWER_TORSO|LEGS|ARMS, heat_parts = UPPER_TORSO|LOWER_TORSO|LEGS|ARMS))

/obj/item/clothing/suit/storage/hazardvest/yw/brigphysician
	name = "Brig Physician Vest"
	desc = "A vest often worn by doctors caring for inmates."
	icon = 'icons/mob/suit_yw.dmi'
	icon_state = "brigphysician-vest"
	icon_override = 'icons/mob/suit_yw.dmi'
	item_state = "brigphysician-vest_s"
	armor_spec = "melee=15;bullet=10;laser=10;energy=10;bomb=10;bio=50;rad=15"

/obj/item/clothing/suit/storage/hazardvest/yw/Paramedic
	name = "Paramedic Vest"
	desc = "A hazard vest used in the recovery of bodies."
	icon = 'icons/mob/suit_yw.dmi'
	icon_state = "paramedic-vest"
	icon_override = 'icons/mob/suit_yw.dmi'
	item_state = "paramedic-vest_s"
	armor_spec = "bomb=15;bio=50;rad=50"
