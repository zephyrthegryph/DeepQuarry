/* Sprites ported from skyrat/tg, serves as an alternative to the virgo versions of certain clothes.
this file deals with suits/overwear. */

// labcoats

// generic labcoat subtypes


// non transforming coats

/obj/item/clothing/suit/neo_gorka
	name = "gorka jacket"
	desc = "it bears a tag that says 'Product of Total Gear & Co.'"
	icon_state = "neo_gorka"

CAPABILITIES(/obj/item/clothing/suit/neo_gorka)
	configure(item_worn(covers = UPPER_TORSO|ARMS))

/obj/item/clothing/suit/neo_gorka_cargo
	name = "cargo gorka"
	desc = "it bears a tag that says 'Product of Total Gear & Co.'"
	icon_state = "neo_gorka_cargo"

CAPABILITIES(/obj/item/clothing/suit/neo_gorka_cargo)
	configure(item_worn(covers = UPPER_TORSO|ARMS))

/obj/item/clothing/suit/neo_runner_coat
	name = "runner's coat"
	desc = "it bears a tag that says 'Product of Total Gear & Co.'"
	icon_state = "neo_runner_coat"

CAPABILITIES(/obj/item/clothing/suit/neo_runner_coat)
	configure(item_worn(covers = UPPER_TORSO|ARMS))

/obj/item/clothing/suit/neo_medical_coat
	name = "medical coat"
	desc = "it bears a tag that says 'Product of Total Gear & Co.'"
	icon_state = "neo_medical_coat"

CAPABILITIES(/obj/item/clothing/suit/neo_medical_coat)
	configure(item_worn(covers = UPPER_TORSO|ARMS))

// non-transforming armoured coats with storage

/obj/item/clothing/suit/storage/vest/wardencoat/neo_bluewarden
	name = "blue warden's jacket"
	desc = "A common style of warden's jacket with armour vest, but in blue. It bears a tag that says 'Product of Total Gear & Co.'"
	icon_state = "neo_bluewarden"

/obj/item/clothing/suit/storage/vest/wardencoat/neo_warden_heavy
	name = "heavy warden coat"
	desc = "A heavy and somewhat-imposing looking armour vest over a long jacket. It bears a tag that says 'Product of Total Gear & Co.'"
	icon_state = "neo_warden_heavy"

/obj/item/clothing/suit/storage/vest/wardencoat/neo_armsco_trench
	name = "armsco heavy coat"
	desc = "A rich red longcoat trimmed in black with a warm brown synthetic fur ruff around the neck, lined with layers of para-aramid fibers for increased durability without compromising comfort. It bears a tag that says 'Product of Total Gear & Co.'"
	icon_state = "neo_armsco_trench"

/obj/item/clothing/suit/storage/vest/hoscoat/neo_hos_parade_jacket
	name = "\improper Head of Security's parade jacket"
	desc = "For when an armoured vest isn't fashionable enough. It bears a tag that says 'Product of Total Gear & Co.'"
	icon_state = "neo_hos_parade_black"
