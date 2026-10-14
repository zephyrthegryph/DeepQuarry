

/obj/item/clothing/gloves/yellow
	desc = "These gloves will protect the wearer from electric shock."
	name = "insulated gloves"
	icon_state = "yellow"


// start: More gloves give cold/heat protection.
// end.

CAPABILITIES(/obj/item/clothing/gloves/yellow)
	configure(item_protection(cold_parts = HANDS, min_cold = GLOVES_MIN_COLD_PROTECTION_TEMPERATURE, heat_parts = HANDS, max_heat = GLOVES_MAX_HEAT_PROTECTION_TEMPERATURE, siemens = 0, permeability = 0.05))
	configure(item_sounds(drop = SFX_ITEMS_DROP_RUBBER, pickup = SFX_ITEMS_PICKUP_RUBBER))

/obj/item/clothing/gloves/fyellow                             //Cheap Chinese Crap
	desc = "These gloves are cheap copies of proper insulated gloves. No way this can end badly."
	name = "budget insulated gloves"
	icon_state = "yellow"

CAPABILITIES(/obj/item/clothing/gloves/fyellow)
	configure(item_protection(siemens = 1, permeability = 0.05))
	configure(item_sounds(drop = SFX_ITEMS_DROP_RUBBER, pickup = SFX_ITEMS_PICKUP_RUBBER))
	after_init(0, then(PROC_REF(roll_insulation)))

/// How well these gloves insulate: a value between 0 and 0.75, in 5% steps, rolled once made.
/obj/item/clothing/gloves/fyellow/proc/roll_insulation(datum/act/timer/A)
	set_siemens_coefficient(rand(0, 15) * 0.05)

/obj/item/clothing/gloves/black
	desc = "These work gloves are thick and fire-resistant."
	name = "black gloves"
	icon_state = "black"
	resistance_flags = FIRE_PROOF

CAPABILITIES(/obj/item/clothing/gloves/black)
	configure(item_protection(permeability = 0.05, min_cold = GLOVES_MIN_COLD_PROTECTION_TEMPERATURE, max_heat = GLOVES_MAX_HEAT_PROTECTION_TEMPERATURE))

/obj/item/clothing/gloves/orange
	name = "orange gloves"
	desc = "A pair of gloves. They look heat-resistant." // Updated description for temp changes.
	icon_state = "orange"

CAPABILITIES(/obj/item/clothing/gloves/orange)
	configure(item_protection(cold_parts = HANDS, min_cold = GLOVES_MIN_COLD_PROTECTION_TEMPERATURE, heat_parts = HANDS, max_heat = GLOVES_MAX_HEAT_PROTECTION_TEMPERATURE))

// start: More gloves give cold/heat protection.
// end.

/obj/item/clothing/gloves/red
	name = "red gloves"
	desc = "A pair of gloves. They look heat-resistant." // Updated description for temp changes.
	icon_state = "red"

CAPABILITIES(/obj/item/clothing/gloves/red)
	configure(item_protection(cold_parts = HANDS, min_cold = GLOVES_MIN_COLD_PROTECTION_TEMPERATURE, heat_parts = HANDS, max_heat = GLOVES_MAX_HEAT_PROTECTION_TEMPERATURE))

// start: More gloves give cold/heat protection.
// end.

/obj/item/clothing/gloves/rainbow
	name = "rainbow gloves"
	desc = "A pair of gloves. They look heat-resistant." // Updated description for temp changes.
	icon_state = "rainbow"

CAPABILITIES(/obj/item/clothing/gloves/rainbow)
	configure(item_protection(cold_parts = HANDS, min_cold = GLOVES_MIN_COLD_PROTECTION_TEMPERATURE, heat_parts = HANDS, max_heat = GLOVES_MAX_HEAT_PROTECTION_TEMPERATURE))

// start: More gloves give cold/heat protection.
// end.

/obj/item/clothing/gloves/blue
	name = "blue gloves"
	desc = "A pair of gloves. They look heat-resistant." // Updated description for temp changes.
	icon_state = "blue"

CAPABILITIES(/obj/item/clothing/gloves/blue)
	configure(item_protection(cold_parts = HANDS, min_cold = GLOVES_MIN_COLD_PROTECTION_TEMPERATURE, heat_parts = HANDS, max_heat = GLOVES_MAX_HEAT_PROTECTION_TEMPERATURE))

// start: More gloves give cold/heat protection.
// end.

/obj/item/clothing/gloves/purple
	name = "purple gloves"
	desc = "A pair of gloves. They look heat-resistant." // Updated description for temp changes.
	icon_state = "purple"

CAPABILITIES(/obj/item/clothing/gloves/purple)
	configure(item_protection(cold_parts = HANDS, min_cold = GLOVES_MIN_COLD_PROTECTION_TEMPERATURE, heat_parts = HANDS, max_heat = GLOVES_MAX_HEAT_PROTECTION_TEMPERATURE))

// start: More gloves give cold/heat protection.
// end.

/obj/item/clothing/gloves/green
	name = "green gloves"
	desc = "A pair of gloves. They look heat-resistant." // Updated description for temp changes.
	icon_state = "green"

CAPABILITIES(/obj/item/clothing/gloves/green)
	configure(item_protection(cold_parts = HANDS, min_cold = GLOVES_MIN_COLD_PROTECTION_TEMPERATURE, heat_parts = HANDS, max_heat = GLOVES_MAX_HEAT_PROTECTION_TEMPERATURE))

// start: More gloves give cold/heat protection.
// end.

/obj/item/clothing/gloves/grey
	name = "grey gloves"
	desc = "A pair of gloves. They look heat-resistant." // Updated description for temp changes.
	icon_state = "gray"

CAPABILITIES(/obj/item/clothing/gloves/grey)
	configure(item_protection(cold_parts = HANDS, min_cold = GLOVES_MIN_COLD_PROTECTION_TEMPERATURE, heat_parts = HANDS, max_heat = GLOVES_MAX_HEAT_PROTECTION_TEMPERATURE))

// start: More gloves give cold/heat protection.
// end.

/obj/item/clothing/gloves/light_brown
	name = "light brown gloves"
	desc = "A pair of gloves. They look heat-resistant." // Updated description for temp changes.
	icon_state = "lightbrown"

CAPABILITIES(/obj/item/clothing/gloves/light_brown)
	configure(item_protection(cold_parts = HANDS, min_cold = GLOVES_MIN_COLD_PROTECTION_TEMPERATURE, heat_parts = HANDS, max_heat = GLOVES_MAX_HEAT_PROTECTION_TEMPERATURE))

// start: More gloves give cold/heat protection.
// end.

/obj/item/clothing/gloves/brown
	name = "brown gloves"
	desc = "A pair of gloves. They look heat-resistant." // Updated description for temp changes.
	icon_state = "brown"

CAPABILITIES(/obj/item/clothing/gloves/brown)
	configure(item_protection(cold_parts = HANDS, min_cold = GLOVES_MIN_COLD_PROTECTION_TEMPERATURE, heat_parts = HANDS, max_heat = GLOVES_MAX_HEAT_PROTECTION_TEMPERATURE))

// start: More gloves give cold/heat protection.
// end.

/obj/item/clothing/gloves/evening
	desc = "A pair of gloves that reach past the elbow.  Fancy!"
	name = "evening gloves"
	icon_state = "evening_gloves"
	addblends = "evening_gloves_a"

CAPABILITIES(/obj/item/clothing/gloves/evening)
	configure(item_protection(heat_parts = ARMS|HANDS, cold_parts = ARMS|HANDS))

/obj/item/clothing/gloves/fingerless
	desc = "A pair of gloves that don't actually cover the fingers."
	name = "fingerless gloves"
	icon_state = "fingerlessgloves"
	fingerprint_chance = 100

/obj/item/clothing/gloves/fingerless/alt
	icon_state = "fingerlessgloves_alt"

/obj/item/clothing/gloves/fingerless/mid
	desc = "A pair of gloves that don't actually cover the fingers. These ones go about halfway up the forearm!"
	name = "long fingerless gloves"
	icon_state = "fingerlessmid_black"

/obj/item/clothing/gloves/fingerless/long
	desc = "A pair of gloves that don't actually cover the fingers. These ones go most of the way to the elbow!"
	name = "elbow-length fingerless gloves"
	icon_state = "fingerlesslong_black"

/obj/item/clothing/gloves/fingerless_recolourable
	desc = "A pair of gloves that don't actually cover the fingers."
	name = "fingerless gloves"
	icon_state = "fingerlessgloves_rc"
	fingerprint_chance = 100

/obj/item/clothing/gloves/fingerless_recolourable/alt
	icon_state = "fingerlessgloves_rc_alt"

/obj/item/clothing/gloves/fingerless_recolourable/mid
	desc = "A pair of gloves that don't actually cover the fingers. These ones go about halfway up the forearm!"
	name = "long fingerless gloves"
	icon_state = "fingerlessmid_white"

/obj/item/clothing/gloves/fingerless_recolourable/long
	desc = "A pair of gloves that don't actually cover the fingers. These ones go most of the way to the elbow!"
	name = "elbow-length fingerless gloves"
	icon_state = "fingerlesslong_white"
