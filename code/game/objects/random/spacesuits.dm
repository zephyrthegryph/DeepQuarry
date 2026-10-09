
// Spaceproof clothing sets go in here

/obj/random/multiple/voidsuit
	name = "Random Voidsuit"
	desc = "This is a random voidsuit."
	icon = 'icons/inventory/suit/item.dmi'
	icon_state = "void"

CAPABILITIES(/obj/random/multiple/voidsuit)
	loot(
		table = list(
			loot_set(5, list(/obj/item/clothing/suit/space/void, /obj/item/clothing/head/helmet/space/void)),
			loot_set(5, list(/obj/item/clothing/suit/space/void/atmos, /obj/item/clothing/head/helmet/space/void/atmos)),
			loot_set(5, list(/obj/item/clothing/suit/space/void/atmos/alt, /obj/item/clothing/head/helmet/space/void/atmos/alt)),
			loot_set(5, list(/obj/item/clothing/suit/space/void/engineering, /obj/item/clothing/head/helmet/space/void/engineering)),
			loot_set(5, list(/obj/item/clothing/suit/space/void/engineering/alt, /obj/item/clothing/head/helmet/space/void/engineering/alt)),
			loot_set(5, list(/obj/item/clothing/suit/space/void/engineering/hazmat, /obj/item/clothing/head/helmet/space/void/engineering/hazmat)),
			loot_set(5, list(/obj/item/clothing/suit/space/void/engineering/construction, /obj/item/clothing/head/helmet/space/void/engineering/construction)),
			loot_set(5, list(/obj/item/clothing/suit/space/void/engineering/salvage, /obj/item/clothing/head/helmet/space/void/engineering/salvage)),
			loot_set(5, list(/obj/item/clothing/suit/space/void/medical, /obj/item/clothing/head/helmet/space/void/medical)),
			loot_set(5, list(/obj/item/clothing/suit/space/void/medical/veymed, /obj/item/clothing/head/helmet/space/void/medical/veymed)),
			loot_set(5, list(/obj/item/clothing/suit/space/void/medical/bio, /obj/item/clothing/head/helmet/space/void/medical/bio)),
			loot_set(5, list(/obj/item/clothing/suit/space/void/medical/emt, /obj/item/clothing/head/helmet/space/void/medical/emt)),
			loot_set(5, list(/obj/item/clothing/suit/space/void/merc, /obj/item/clothing/head/helmet/space/void/merc)),
			loot_set(5, list(/obj/item/clothing/suit/space/void/merc/fire, /obj/item/clothing/head/helmet/space/void/merc/fire)),
			loot_set(5, list(/obj/item/clothing/suit/space/void/mining, /obj/item/clothing/head/helmet/space/void/mining)),
			loot_set(5, list(/obj/item/clothing/suit/space/void/mining/alt, /obj/item/clothing/head/helmet/space/void/mining/alt)),
			loot_set(5, list(/obj/item/clothing/suit/space/void/security, /obj/item/clothing/head/helmet/space/void/security)),
			loot_set(5, list(/obj/item/clothing/suit/space/void/security/alt, /obj/item/clothing/head/helmet/space/void/security/alt)),
			loot_set(5, list(/obj/item/clothing/suit/space/void/security/riot, /obj/item/clothing/head/helmet/space/void/security/riot)),
			loot_set(5, list(/obj/item/clothing/suit/space/void/exploration, /obj/item/clothing/head/helmet/space/void/exploration)),
			loot_set(5, list(/obj/item/clothing/suit/space/void/pilot, /obj/item/clothing/head/helmet/space/void/pilot))))

/obj/random/multiple/voidsuit/mining
	name = "Random Mining Voidsuit"
	desc = "This is a random mining voidsuit."
	icon = 'icons/inventory/suit/item.dmi'
	icon_state = "rig-mining"

CAPABILITIES(/obj/random/multiple/voidsuit/mining)
	configure(loot(
		table = list(
			loot_set(5, list(/obj/item/clothing/suit/space/void/mining, /obj/item/clothing/head/helmet/space/void/mining)),
			loot_set(1, list(/obj/item/clothing/suit/space/void/mining/alt, /obj/item/clothing/head/helmet/space/void/mining/alt)))))

/obj/random/multiple/voidsuit/engineering
	name = "Random Engineering Voidsuit"
	desc = "This is a random engineering voidsuit."
	icon = 'icons/inventory/suit/item.dmi'
	icon_state = "rig-engineering"

CAPABILITIES(/obj/random/multiple/voidsuit/engineering)
	configure(loot(
		table = list(
			loot_set(35, list(/obj/item/clothing/suit/space/void/engineering, /obj/item/clothing/head/helmet/space/void/engineering)),
			loot_set(5, list(/obj/item/clothing/suit/space/void/engineering/alt, /obj/item/clothing/head/helmet/space/void/engineering/alt)),
			loot_set(15, list(/obj/item/clothing/suit/space/void/engineering/hazmat, /obj/item/clothing/head/helmet/space/void/engineering/hazmat)),
			loot_set(15, list(/obj/item/clothing/suit/space/void/engineering/construction, /obj/item/clothing/head/helmet/space/void/engineering/construction)),
			loot_set(5, list(/obj/item/clothing/suit/space/void/engineering/salvage, /obj/item/clothing/head/helmet/space/void/engineering/salvage)))))

/obj/random/multiple/voidsuit/security
	name = "Random Security Voidsuit"
	desc = "This is a random security voidsuit."
	icon = 'icons/inventory/suit/item.dmi'
	icon_state = "rig-sec"

CAPABILITIES(/obj/random/multiple/voidsuit/security)
	configure(loot(
		table = list(
			loot_set(10, list(/obj/item/clothing/suit/space/void/security, /obj/item/clothing/head/helmet/space/void/security)),
			loot_set(5, list(/obj/item/clothing/suit/space/void/security/alt, /obj/item/clothing/head/helmet/space/void/security/alt)),
			loot_set(5, list(/obj/item/clothing/suit/space/void/security/riot, /obj/item/clothing/head/helmet/space/void/security/riot)))))

/obj/random/multiple/voidsuit/medical
	name = "Random Medical Voidsuit"
	desc = "This is a random medical voidsuit."
	icon = 'icons/inventory/suit/item.dmi'
	icon_state = "rig-medical"

CAPABILITIES(/obj/random/multiple/voidsuit/medical)
	configure(loot(
		table = list(
			loot_set(5, list(/obj/item/clothing/suit/space/void/medical, /obj/item/clothing/head/helmet/space/void/medical)),
			loot_set(1, list(/obj/item/clothing/suit/space/void/medical/veymed, /obj/item/clothing/head/helmet/space/void/medical/veymed)),
			loot_set(3, list(/obj/item/clothing/suit/space/void/medical/bio, /obj/item/clothing/head/helmet/space/void/medical/bio)),
			loot_set(4, list(/obj/item/clothing/suit/space/void/medical/emt, /obj/item/clothing/head/helmet/space/void/medical/emt)))))

/obj/random/multiple/voidsuit/vintage
	name = "Random Vintage Voidsuit"
	desc = "This is a random vintage voidsuit."
	icon = 'icons/inventory/suit/item.dmi'
	icon_state = "rig-vintagecrew"

CAPABILITIES(/obj/random/multiple/voidsuit/vintage)
	configure(loot(
		table = list(
			loot_set(20, list(/obj/item/clothing/suit/space/void/refurb, /obj/item/clothing/head/helmet/space/void/refurb)),
			loot_set(20, list(/obj/item/clothing/suit/space/void/refurb/engineering, /obj/item/clothing/head/helmet/space/void/refurb/engineering)),
			loot_set(10, list(/obj/item/clothing/suit/space/void/refurb/medical, /obj/item/clothing/head/helmet/space/void/refurb/medical)),
			loot_set(10, list(/obj/item/clothing/suit/space/void/refurb/medical, /obj/item/clothing/head/helmet/space/void/refurb/medical/alt)),
			loot_set(10, list(/obj/item/clothing/suit/space/void/refurb/marine, /obj/item/clothing/head/helmet/space/void/refurb/marine)),
			loot_set(5, list(/obj/item/clothing/suit/space/void/refurb/officer, /obj/item/clothing/head/helmet/space/void/refurb/officer)),
			loot_set(10, list(/obj/item/clothing/suit/space/void/refurb/pilot, /obj/item/clothing/head/helmet/space/void/refurb/pilot)),
			loot_set(10, list(/obj/item/clothing/suit/space/void/refurb/pilot, /obj/item/clothing/head/helmet/space/void/refurb/pilot/alt)),
			loot_set(10, list(/obj/item/clothing/suit/space/void/refurb/research, /obj/item/clothing/head/helmet/space/void/refurb/research)),
			loot_set(10, list(/obj/item/clothing/suit/space/void/refurb/research, /obj/item/clothing/head/helmet/space/void/refurb/research/alt)),
			loot_set(10, list(/obj/item/clothing/suit/space/void/refurb/mining, /obj/item/clothing/head/helmet/space/void/refurb/mining)),
			loot_set(5, list(/obj/item/clothing/suit/space/void/refurb/mercenary, /obj/item/clothing/head/helmet/space/void/refurb/mercenary)))))

/obj/random/rigsuit
	name = "Random rigsuit"
	desc = "This is a random rigsuit."
	icon = 'icons/obj/rig_modules.dmi'
	icon_state = "generic"

CAPABILITIES(/obj/random/rigsuit)
	loot(
		table = list(
			/obj/item/rig/light/hacker = 4,
			/obj/item/rig/industrial = 5,
			/obj/item/rig/eva = 5,
			/obj/item/rig/hazard = 3,
			/obj/item/rig/merc/empty = 1,
			/obj/item/rig/light/stealth = 4))
/obj/random/rigsuit/chancetofail
CAPABILITIES(/obj/random/rigsuit/chancetofail)
	configure(loot(chance = 50))
