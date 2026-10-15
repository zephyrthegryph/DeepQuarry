//Updated
/datum/power/changeling/space_suit
	name = "Organic Space Suit"
	desc = "We grow an organic suit to protect ourselves from space exposure."
	helptext = "To remove the suit, use the ability again."
	ability_icon_state = "ling_space_suit"
	genomecost = 0 //Have a free spacesuit. It's not worth buying. If you want a special version, get the armor.
	verbpath = /mob/proc/changeling_spacesuit

/mob/proc/changeling_spacesuit()
	set category = VERB_CAT_CHANGELING
	set name = "Organic Space Suit (20)"
	if(changeling_generic_armor(/obj/item/clothing/suit/space/changeling,/obj/item/clothing/head/helmet/space/changeling,/obj/item/clothing/shoes/magboots/changeling, 20))
		return 1
	return 0

/datum/power/changeling/armor
	name = "Chitinous Spacearmor"
	desc = "We turn our skin into tough chitin to protect us from damage and space exposure."
	helptext = "To remove the armor, use the ability again."
	ability_icon_state = "ling_armor"
	genomecost = 3
	verbpath = /mob/proc/changeling_spacearmor

/mob/proc/changeling_spacearmor()
	set category = VERB_CAT_CHANGELING
	set name = "Organic Spacearmor (20)"

	if(changeling_generic_armor(/obj/item/clothing/suit/space/changeling/armored,/obj/item/clothing/head/helmet/space/changeling/armored,/obj/item/clothing/shoes/magboots/changeling/armored, 20))
		return 1
	return 0

//Space suit

/obj/item/clothing/suit/space/changeling
	name = "flesh mass"
	icon_state = "lingspacesuit"
	desc = "A huge, bulky mass of pressure and temperature-resistant organic tissue, evolved to facilitate space travel."
	flags = NONE	//Not THICKMATERIAL because it's organic tissue, so if somebody tries to inject something into it,
				//it still ends up in your blood. (also balance but muh fluff)
	armor_spec = "cold=60" //No armor at all.
	canremove = FALSE

CAPABILITIES(/obj/item/clothing/suit/space/changeling)
	acceptance(CONSTRAINT_SUIT_STORAGE, req_acceptance_type(list(POCKET_GENERIC, POCKET_ALL_TANKS), because = "it doesn't take that"), mode = ACCEPTANCE_REPLACE)
	configure(item_worn(flags = THICKMATERIAL | DROPDEL | NOSTRIP))


/obj/item/clothing/suit/space/changeling/Initialize(mapload)
	. = ..()
	if(ismob(loc))
		loc.visible_message(span_warning("[loc.name]\'s flesh rapidly inflates, forming a bloated mass around their body!"),
		span_warning("We inflate our flesh, creating a spaceproof suit!"),
		span_warningplain("You hear organic matter ripping and tearing!"))

/obj/item/clothing/head/helmet/space/changeling
	name = "flesh mass"
	icon_state = "lingspacehelmet"
	desc = "A covering of pressure and temperature-resistant organic tissue with a glass-like chitin front."
	flags = BLOCKHAIR //Again, no THICKMATERIAL.
	armor_spec = "cold=60"
	canremove = FALSE

CAPABILITIES(/obj/item/clothing/head/helmet/space/changeling)
	configure(item_worn(covers = HEAD|FACE|EYES, flags = THICKMATERIAL | AIRTIGHT | FLEXIBLEMATERIAL | DROPDEL | NOSTRIP))

/obj/item/clothing/shoes/magboots/changeling
	desc = "A suction cupped mass of flesh, shaped like a foot."
	name = "fleshy grippers"
	icon_state = "lingspacesuit"
	actions_types = list(/datum/action/item_action/toggle_grippers)
	canremove = FALSE

CAPABILITIES(/obj/item/clothing/shoes/magboots/changeling)
	configure(item_worn(flags = DROPDEL | NOSTRIP))

/obj/item/clothing/shoes/magboots/changeling/set_slowdown()
	slowdown = shoes? max(SHOES_SLOWDOWN, shoes.slowdown): SHOES_SLOWDOWN	//So you can't put on magboots to make you walk faster.
	if (magpulse)
		slowdown += 1		//It's already tied to a slowdown suit, 6 slowdown is huge.

/// Old attack_self. Runs the magboots toggle first, as the old ..() did (so it toggles twice; kept as it was). The parent's op ("magboots_toggle_self")
/// reaches this override.
/obj/item/clothing/shoes/magboots/changeling/magboots_toggle_self(datum/act/op/A)
	var/mob/user = A.actor
	..()
	if(magpulse)
		set_item_flags(worn_of(src).flags & (~NOSLIP))
		magpulse = 0
		set_slowdown()
		set_force(3)
		to_chat(user, "We release our grip on the floor.")
	else
		set_item_flags(worn_of(src).flags | (NOSLIP))
		magpulse = 1
		set_slowdown()
		set_force(5)
		to_chat(user, "We cling to the terrain below us.")

//Armor

/obj/item/clothing/suit/space/changeling/armored
	name = "chitinous mass"
	desc = "A tough, hard covering of black chitin."
	icon_state = "lingarmor"
	armor_spec = "melee=75;bullet=60;laser=60;energy=60;bomb=60;cold=60" //It costs 3 points, so it should be very protective.
	slowdown = 1.5

CAPABILITIES(/obj/item/clothing/suit/space/changeling/armored)
	configure(item_worn(covers = CHEST|LEGS|FEET|ARMS|HANDS))
	configure(item_protection(siemens = 0.3, max_heat = FIRESUIT_MAX_HEAT_PROTECTION_TEMPERATURE))

/obj/item/clothing/suit/space/changeling/armored/Initialize(mapload)
	. = ..()
	if(ismob(loc))
		loc.visible_message(span_warning("[loc.name]\'s flesh turns black, quickly transforming into a hard, chitinous mass!"),
		span_warning("We harden our flesh, creating a suit of armor!"),
		span_warningplain("You hear organic matter ripping and tearing!"))

/obj/item/clothing/head/helmet/space/changeling/armored
	name = "chitinous mass"
	desc = "A tough, hard covering of black chitin with transparent chitin in front."
	icon_state = "lingarmorhelmet"
	armor_spec = "melee=75;bullet=60;laser=60;energy=60;bomb=60;cold=60"

CAPABILITIES(/obj/item/clothing/head/helmet/space/changeling/armored)
	configure(item_protection(siemens = 0.3, max_heat = FIRE_HELMET_MAX_HEAT_PROTECTION_TEMPERATURE))

/obj/item/clothing/shoes/magboots/changeling/armored
	desc = "A tough, hard mass of chitin, with long talons for digging into terrain."
	name = "chitinous talons"
	icon_state = "lingarmor"
	actions_types = list(/datum/action/item_action/toggle_talons)

/obj/item/clothing/gloves/combat/changeling //Combined insulated/fireproof gloves
	name = "chitinous gauntlets"
	desc = "Very resilient gauntlets made out of black chitin.  It looks very durable, and can probably resist electrical shock in addition to the elements."
	icon_state = "ling"
	armor_spec = "melee=75;bullet=60;laser=60;energy=60;bomb=60" //No idea if glove armor gets checked

CAPABILITIES(/obj/item/clothing/gloves/combat/changeling)
	configure(item_protection(siemens = 0))

/obj/item/clothing/shoes/boots/combat/changeling //Noslips
	name = "chitinous boots"
	desc = "Footwear made out of a hard, black chitinous material.  The bottoms of these appear to have spikes that can protrude or extract itself into and out \
	of the floor at will, granting the wearer stability."
	icon_state = "lingarmor"
	armor_spec = "melee=75;bullet=60;laser=70;energy=60;bomb=60"

CAPABILITIES(/obj/item/clothing/shoes/boots/combat/changeling)
	configure(item_protection(siemens = 0.3, min_cold = SHOE_MIN_COLD_PROTECTION_TEMPERATURE, max_heat = SHOE_MAX_HEAT_PROTECTION_TEMPERATURE))
