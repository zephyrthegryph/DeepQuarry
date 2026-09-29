
// Spaceproof clothing sets go in here

/obj/random/multiple/voidsuit
	name = "Random Voidsuit"
	desc = "This is a random voidsuit."
	icon = 'icons/inventory/suit/item.dmi'
	icon_state = "void"

DECLARE_LOOT(/obj/random/multiple/voidsuit, LOOT_TABLE(\
	LOOT_SET(5, /obj/item/clothing/suit/space/void, /obj/item/clothing/head/helmet/space/void), \
	LOOT_SET(5, /obj/item/clothing/suit/space/void/atmos, /obj/item/clothing/head/helmet/space/void/atmos), \
	LOOT_SET(5, /obj/item/clothing/suit/space/void/atmos/alt, /obj/item/clothing/head/helmet/space/void/atmos/alt), \
	LOOT_SET(5, /obj/item/clothing/suit/space/void/engineering, /obj/item/clothing/head/helmet/space/void/engineering), \
	LOOT_SET(5, /obj/item/clothing/suit/space/void/engineering/alt, /obj/item/clothing/head/helmet/space/void/engineering/alt), \
	LOOT_SET(5, /obj/item/clothing/suit/space/void/engineering/hazmat, /obj/item/clothing/head/helmet/space/void/engineering/hazmat), \
	LOOT_SET(5, /obj/item/clothing/suit/space/void/engineering/construction, /obj/item/clothing/head/helmet/space/void/engineering/construction), \
	LOOT_SET(5, /obj/item/clothing/suit/space/void/engineering/salvage, /obj/item/clothing/head/helmet/space/void/engineering/salvage), \
	LOOT_SET(5, /obj/item/clothing/suit/space/void/medical, /obj/item/clothing/head/helmet/space/void/medical), \
	LOOT_SET(5, /obj/item/clothing/suit/space/void/medical/veymed, /obj/item/clothing/head/helmet/space/void/medical/veymed), \
	LOOT_SET(5, /obj/item/clothing/suit/space/void/medical/bio, /obj/item/clothing/head/helmet/space/void/medical/bio), \
	LOOT_SET(5, /obj/item/clothing/suit/space/void/medical/emt, /obj/item/clothing/head/helmet/space/void/medical/emt), \
	LOOT_SET(5, /obj/item/clothing/suit/space/void/merc, /obj/item/clothing/head/helmet/space/void/merc), \
	LOOT_SET(5, /obj/item/clothing/suit/space/void/merc/fire, /obj/item/clothing/head/helmet/space/void/merc/fire), \
	LOOT_SET(5, /obj/item/clothing/suit/space/void/mining, /obj/item/clothing/head/helmet/space/void/mining), \
	LOOT_SET(5, /obj/item/clothing/suit/space/void/mining/alt, /obj/item/clothing/head/helmet/space/void/mining/alt), \
	LOOT_SET(5, /obj/item/clothing/suit/space/void/security, /obj/item/clothing/head/helmet/space/void/security), \
	LOOT_SET(5, /obj/item/clothing/suit/space/void/security/alt, /obj/item/clothing/head/helmet/space/void/security/alt), \
	LOOT_SET(5, /obj/item/clothing/suit/space/void/security/riot, /obj/item/clothing/head/helmet/space/void/security/riot), \
	LOOT_SET(5, /obj/item/clothing/suit/space/void/exploration, /obj/item/clothing/head/helmet/space/void/exploration), \
	LOOT_SET(5, /obj/item/clothing/suit/space/void/pilot, /obj/item/clothing/head/helmet/space/void/pilot)))

/obj/random/multiple/voidsuit/mining
	name = "Random Mining Voidsuit"
	desc = "This is a random mining voidsuit."
	icon = 'icons/inventory/suit/item.dmi'
	icon_state = "rig-mining"

DECLARE_LOOT(/obj/random/multiple/voidsuit/mining, LOOT_TABLE(\
	LOOT_SET(5, /obj/item/clothing/suit/space/void/mining, /obj/item/clothing/head/helmet/space/void/mining), \
	LOOT_SET(1, /obj/item/clothing/suit/space/void/mining/alt, /obj/item/clothing/head/helmet/space/void/mining/alt)))

/obj/random/multiple/voidsuit/engineering
	name = "Random Engineering Voidsuit"
	desc = "This is a random engineering voidsuit."
	icon = 'icons/inventory/suit/item.dmi'
	icon_state = "rig-engineering"

DECLARE_LOOT(/obj/random/multiple/voidsuit/engineering, LOOT_TABLE(\
	LOOT_SET(35, /obj/item/clothing/suit/space/void/engineering, /obj/item/clothing/head/helmet/space/void/engineering), \
	LOOT_SET(5, /obj/item/clothing/suit/space/void/engineering/alt, /obj/item/clothing/head/helmet/space/void/engineering/alt), \
	LOOT_SET(15, /obj/item/clothing/suit/space/void/engineering/hazmat, /obj/item/clothing/head/helmet/space/void/engineering/hazmat), \
	LOOT_SET(15, /obj/item/clothing/suit/space/void/engineering/construction, /obj/item/clothing/head/helmet/space/void/engineering/construction), \
	LOOT_SET(5, /obj/item/clothing/suit/space/void/engineering/salvage, /obj/item/clothing/head/helmet/space/void/engineering/salvage)))

/obj/random/multiple/voidsuit/security
	name = "Random Security Voidsuit"
	desc = "This is a random security voidsuit."
	icon = 'icons/inventory/suit/item.dmi'
	icon_state = "rig-sec"

DECLARE_LOOT(/obj/random/multiple/voidsuit/security, LOOT_TABLE(\
	LOOT_SET(10, /obj/item/clothing/suit/space/void/security, /obj/item/clothing/head/helmet/space/void/security), \
	LOOT_SET(5, /obj/item/clothing/suit/space/void/security/alt, /obj/item/clothing/head/helmet/space/void/security/alt), \
	LOOT_SET(5, /obj/item/clothing/suit/space/void/security/riot, /obj/item/clothing/head/helmet/space/void/security/riot)))

/obj/random/multiple/voidsuit/medical
	name = "Random Medical Voidsuit"
	desc = "This is a random medical voidsuit."
	icon = 'icons/inventory/suit/item.dmi'
	icon_state = "rig-medical"

DECLARE_LOOT(/obj/random/multiple/voidsuit/medical, LOOT_TABLE(\
	LOOT_SET(5, /obj/item/clothing/suit/space/void/medical, /obj/item/clothing/head/helmet/space/void/medical), \
	LOOT_SET(1, /obj/item/clothing/suit/space/void/medical/veymed, /obj/item/clothing/head/helmet/space/void/medical/veymed), \
	LOOT_SET(3, /obj/item/clothing/suit/space/void/medical/bio, /obj/item/clothing/head/helmet/space/void/medical/bio), \
	LOOT_SET(4, /obj/item/clothing/suit/space/void/medical/emt, /obj/item/clothing/head/helmet/space/void/medical/emt)))

/obj/random/multiple/voidsuit/vintage
	name = "Random Vintage Voidsuit"
	desc = "This is a random vintage voidsuit."
	icon = 'icons/inventory/suit/item.dmi'
	icon_state = "rig-vintagecrew"

DECLARE_LOOT(/obj/random/multiple/voidsuit/vintage, LOOT_TABLE(\
	LOOT_SET(20, /obj/item/clothing/suit/space/void/refurb, /obj/item/clothing/head/helmet/space/void/refurb), \
	LOOT_SET(20, /obj/item/clothing/suit/space/void/refurb/engineering, /obj/item/clothing/head/helmet/space/void/refurb/engineering), \
	LOOT_SET(10, /obj/item/clothing/suit/space/void/refurb/medical, /obj/item/clothing/head/helmet/space/void/refurb/medical), \
	LOOT_SET(10, /obj/item/clothing/suit/space/void/refurb/medical, /obj/item/clothing/head/helmet/space/void/refurb/medical/alt), \
	LOOT_SET(10, /obj/item/clothing/suit/space/void/refurb/marine, /obj/item/clothing/head/helmet/space/void/refurb/marine), \
	LOOT_SET(5, /obj/item/clothing/suit/space/void/refurb/officer, /obj/item/clothing/head/helmet/space/void/refurb/officer), \
	LOOT_SET(10, /obj/item/clothing/suit/space/void/refurb/pilot, /obj/item/clothing/head/helmet/space/void/refurb/pilot), \
	LOOT_SET(10, /obj/item/clothing/suit/space/void/refurb/pilot, /obj/item/clothing/head/helmet/space/void/refurb/pilot/alt), \
	LOOT_SET(10, /obj/item/clothing/suit/space/void/refurb/research, /obj/item/clothing/head/helmet/space/void/refurb/research), \
	LOOT_SET(10, /obj/item/clothing/suit/space/void/refurb/research, /obj/item/clothing/head/helmet/space/void/refurb/research/alt), \
	LOOT_SET(10, /obj/item/clothing/suit/space/void/refurb/mining, /obj/item/clothing/head/helmet/space/void/refurb/mining), \
	LOOT_SET(5, /obj/item/clothing/suit/space/void/refurb/mercenary, /obj/item/clothing/head/helmet/space/void/refurb/mercenary)))

/obj/random/rigsuit
	name = "Random rigsuit"
	desc = "This is a random rigsuit."
	icon = 'icons/obj/rig_modules.dmi'
	icon_state = "generic"

DECLARE_LOOT(/obj/random/rigsuit, LOOT_TABLE(\
	/obj/item/rig/light/hacker = 4, \
	/obj/item/rig/industrial = 5, \
	/obj/item/rig/eva = 5, \
	/obj/item/rig/hazard = 3, \
	/obj/item/rig/merc/empty = 1, \
	/obj/item/rig/light/stealth = 4))
/obj/random/rigsuit/chancetofail
DECLARE_LOOT(/obj/random/rigsuit/chancetofail, LOOT_CHANCE(50))
