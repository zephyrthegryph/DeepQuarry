/obj/machinery/vending/food/prison
	name = "Prison Nutriment Vendor"
	desc = "Delicious, probably not."
	icon_state = "fridge_dark"
	vend_delay = 15

/obj/machinery/vending/security/yw
	name = "SecTech"
	desc = "A security equipment vendor."
	product_ads = "Crack capitalist skulls!;Beat some heads in!;Don't forget - harm is good!;Your weapons are right here.;Handcuffs!;Freeze, scumbag!;Don't tase me bro!;Tase them, bro.;Why not have a donut?"
	icon_state = "sec"
	req_access = list(ACCESS_SECURITY)
	req_log_access = ACCESS_ARMORY
	has_logs = 1

/* CONTAINS:
	Explo equipment vending machines
	Sec equipment vending machines
*/

/obj/machinery/vending/exploration_armor
	name = "Exploration Equipment Vendor"
	desc = "A large vending machine stocked with surplus uniforms, armor and pouches for exploration members."
	vend_delay = 1
	icon_state = "sec" // Placeholder
	req_one_access = list(ACCESS_EXPLORER,ACCESS_PILOT,ACCESS_MEDICAL_EQUIP)

/obj/machinery/vending/exploration_weapons
	name = "Exploration Weapon Vendor"
	desc = "A large vending machine stocked with surplus phase, laser and ballistic weaponry for exploration members."
	vend_delay = 1
	icon_state = "sec" // Placeholder
	req_one_access = list(ACCESS_EXPLORER,ACCESS_PILOT,ACCESS_MEDICAL_EQUIP)

/obj/machinery/vending/exploration_misc
	name = "Exploration Misc Vendor"
	desc = "A large vending machine stocked with an assortment of miscellaneous equipment handy for explorers."
	vend_delay = 1
	icon_state = "sec" // Placeholder
	req_one_access = list(ACCESS_EXPLORER,ACCESS_PILOT,ACCESS_MEDICAL_EQUIP)

/obj/machinery/vending/exploration_pilot
	name = "Pilot Equipment Vendor"
	desc = "A large vending machine stocked with surplus uniforms and equipment for pilots."
	vend_delay = 1
	icon_state = "sec" // Placeholder
	req_access = list(ACCESS_PILOT)

/obj/machinery/vending/exploration_fieldmedic
	name = "Field Medic Equipment Vendor"
	desc = "A large vending machine stocked with surplus uniforms and equipment for field medics."
	vend_delay = 1
	icon_state = "sec" // Placeholder
	req_access = list(ACCESS_MEDICAL_EQUIP)

/obj/machinery/vending/security_armor
	name = "Security Plate Carrier Vendor"
	desc = "A large vending machine stocked with plate carriers and accessories to accompany them."
	vend_delay = 1
	icon_state = "sec"
	req_access = list(ACCESS_SECURITY)

/obj/machinery/vending/security_armory_armor
	name = "Security Armory Plate Carrier Vendor"
	desc = "A large vending machine stocked with advanced plate carriers and improved accessories to accompany them."
	vend_delay = 1
	icon_state = "sec"
	req_access = list(ACCESS_SECURITY)

//Temp Starhunter Fix
/obj/machinery/vending/starhunter_farmer
	name = "Starhunter Trade Vendor: Farming"
	desc = "A large vending machine stocked with strange farming goods."
	vend_delay = 1
	icon_state = "sec" // Placeholder
	products	= list(/obj/item/slime_extract/sepia =3,
		/obj/item/slime_extract/ruby = 3,
		/obj/item/slime_extract/bluespace = 3,
		/obj/item/slime_extract/oil = 3,
		/obj/item/slime_extract/sapphire = 3,
		/obj/item/slime_extract/emerald = 3,
		VARIANT(/obj/item/seeds/shrinkshroom) = 12,
		VARIANT(/obj/item/seeds/megashroom) = 12,
		VARIANT(/obj/item/seeds/pitcherseed) = 6,
		VARIANT(/obj/item/seeds/deathberryseed) = 6,
		VARIANT(/obj/item/seeds/ambrosiainfernusseed) = 6,
		VARIANT(/obj/item/seeds/thaadra) = 6,
		VARIANT(/obj/item/seeds/icepepperseed) = 6,
		VARIANT(/obj/item/seeds/jurlmah) = 6,
		VARIANT(/obj/item/seeds/amauri) = 6,
		VARIANT(/obj/item/seeds/gelthi) = 6,
		VARIANT(/obj/item/seeds/vale) = 6
		) // For each, use the following pattern:

	premium 	= list() // No specified amount = only one in stock

	prices     = list(/obj/item/slime_extract/sepia = 2250,
		/obj/item/slime_extract/ruby = 3250,
		/obj/item/slime_extract/bluespace = 3250,
		/obj/item/slime_extract/oil = 3250,
		/obj/item/slime_extract/sapphire = 3250,
		/obj/item/slime_extract/emerald = 3250,
		VARIANT(/obj/item/seeds/shrinkshroom) = 50,
		VARIANT(/obj/item/seeds/megashroom) = 50,
		VARIANT(/obj/item/seeds/pitcherseed) = 125,
		VARIANT(/obj/item/seeds/deathberryseed) = 125,
		VARIANT(/obj/item/seeds/ambrosiainfernusseed) = 125,
		VARIANT(/obj/item/seeds/thaadra) = 125,
		VARIANT(/obj/item/seeds/icepepperseed) = 125,
		VARIANT(/obj/item/seeds/jurlmah) = 125,
		VARIANT(/obj/item/seeds/amauri) = 125,
		VARIANT(/obj/item/seeds/gelthi) = 125,
		VARIANT(/obj/item/seeds/vale) = 125)

/obj/machinery/vending/starhunter_miner
	name = "Starhunter Trade Vendor: Miner"
	desc = "A large vending machine stocked with strange mining goods."
	vend_delay = 1
	icon_state = "sec" // Placeholder
	products	= list(/obj/item/kinetic_crusher/glaive = 3,
		/obj/item/kinetic_crusher = 3,
		/obj/item/gun/energy/mininglaser = 3,
		/obj/item/stack/material/phoron = 50,
		/obj/item/stack/material/uranium = 50,
		/obj/item/stack/material/tritium = 50,
		/obj/item/stack/material/deuterium = 50,
		/obj/item/stack/material/bronze = 50,
		) // For each, use the following pattern:

	premium 	= list(VARIANT(/obj/item/circuitboard/defenseonelisk)) // No specified amount = only one in stock

	prices     = list(/obj/item/kinetic_crusher/glaive = 1200,
		/obj/item/kinetic_crusher = 1200,
		/obj/item/gun/energy/mininglaser = 1800,
		/obj/item/stack/material/phoron = 12,
		/obj/item/stack/material/uranium = 12,
		/obj/item/stack/material/tritium = 12,
		/obj/item/stack/material/deuterium = 12,
		/obj/item/stack/material/bronze = 12,
		VARIANT(/obj/item/circuitboard/defenseonelisk) = 5000
		)

//Some stuff to let sec do things
/obj/machinery/vending/nifsoft_shop
	req_log_access = ACCESS_SECURITY
	has_logs = 1
