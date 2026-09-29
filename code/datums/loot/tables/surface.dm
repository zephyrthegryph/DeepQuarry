// Searchable loot tables (loot_search(), code/datums/loot/loot.dm). Each declaration is complete:
// it carries every tier and setting it had, inherited ones included.

// Surface loot piles are considerably harder and more dangerous to reach, so you're more likely to get rare things.
DECLARE_LOOT(/loot/surface, \
	LOOT_DEPLETION(5, FALSE))

// Base type for alien piles.
DECLARE_LOOT(/loot/surface/alien, \
	LOOT_TABLE(\
		/obj/item/prop/alien/junk), \
	LOOT_DEPLETION(5, FALSE))

// May contain alien tools.
DECLARE_LOOT(/loot/surface/alien/engineering, \
	LOOT_TABLE(\
		/obj/item/prop/alien/junk), \
	LOOT_UNCOMMON(20, \
		/obj/item/multitool/alien, \
		/obj/item/stack/cable_coil/alien, \
		/obj/item/tool/crowbar/alien, \
		/obj/item/tool/screwdriver/alien, \
		/obj/item/weldingtool/alien, \
		/obj/item/tool/wirecutters/alien, \
		/obj/item/tool/wrench/alien), \
	LOOT_RARE(5, \
		/obj/item/storage/belt/utility/alien/full), \
	LOOT_DEPLETION(5, FALSE))

// May contain alien surgery equipment or powerful medication.
DECLARE_LOOT(/loot/surface/alien/medical, \
	LOOT_TABLE(\
		/obj/item/prop/alien/junk), \
	LOOT_UNCOMMON(20, \
		/obj/item/surgical/FixOVein/alien, \
		/obj/item/surgical/bone_clamp/alien, \
		/obj/item/surgical/cautery/alien, \
		/obj/item/surgical/circular_saw/alien, \
		/obj/item/surgical/hemostat/alien, \
		/obj/item/surgical/retractor/alien, \
		/obj/item/surgical/scalpel/alien, \
		/obj/item/surgical/surgicaldrill/alien), \
	LOOT_RARE(5, \
		/obj/item/storage/belt/medical/alien), \
	LOOT_DEPLETION(5, FALSE))

// May contain powercells or alien weaponry.
DECLARE_LOOT(/loot/surface/alien/security, \
	LOOT_TABLE(\
		/obj/item/prop/alien/junk), \
	LOOT_UNCOMMON(20, \
		/obj/item/cell/device/weapon/recharge/alien, \
		/obj/item/clothing/suit/armor/alien, \
		/obj/item/clothing/head/helmet/alien), \
	LOOT_RARE(5, \
		/obj/item/clothing/suit/armor/alien/tank, \
		/obj/item/gun/energy/alien), \
	LOOT_DEPLETION(5, FALSE))

// The pile found at the very end, and as such has the best loot.
DECLARE_LOOT(/loot/surface/alien/end, \
	LOOT_TABLE(\
		/obj/item/multitool/alien, \
		/obj/item/stack/cable_coil/alien, \
		/obj/item/tool/crowbar/alien, \
		/obj/item/tool/screwdriver/alien, \
		/obj/item/weldingtool/alien, \
		/obj/item/tool/wirecutters/alien, \
		/obj/item/tool/wrench/alien, \
		/obj/item/surgical/FixOVein/alien, \
		/obj/item/surgical/bone_clamp/alien, \
		/obj/item/surgical/cautery/alien, \
		/obj/item/surgical/circular_saw/alien, \
		/obj/item/surgical/hemostat/alien, \
		/obj/item/surgical/retractor/alien, \
		/obj/item/surgical/scalpel/alien, \
		/obj/item/surgical/surgicaldrill/alien, \
		/obj/item/cell/device/weapon/recharge/alien, \
		/obj/item/clothing/suit/armor/alien, \
		/obj/item/clothing/head/helmet/alien, \
		/obj/item/gun/energy/alien), \
	LOOT_UNCOMMON(30, \
		/obj/item/storage/belt/medical/alien, \
		/obj/item/storage/belt/utility/alien/full, \
		/obj/item/clothing/suit/armor/alien/tank, \
		/obj/item/clothing/head/helmet/alien/tank), \
	LOOT_DEPLETION(5, FALSE))

// POI bones of other less fortunate explos
DECLARE_LOOT(/loot/surface/bones, \
	LOOT_TABLE(\
		/obj/item/bone, \
		/obj/item/bone/skull, \
		/obj/item/bone/skull/tajaran, \
		/obj/item/bone/skull/unathi, \
		/obj/item/bone/skull/unknown, \
		/obj/item/bone/leg, \
		/obj/item/bone/arm, \
		/obj/item/bone/ribs), \
	LOOT_UNCOMMON(20, \
		/obj/item/coin/gold, \
		/obj/item/coin/silver, \
		/obj/item/deck/tarot, \
		/obj/item/flame/lighter/zippo/gold, \
		/obj/item/flame/lighter/zippo/black, \
		/obj/item/material/knife/tacknife/survival, \
		/obj/item/material/knife/tacknife/combatknife, \
		/obj/item/material/knife/machete/hatchet, \
		/obj/item/material/knife/butch, \
		/obj/item/storage/wallet/random, \
		/obj/item/clothing/accessory/bracelet/material/gold, \
		/obj/item/clothing/accessory/bracelet/material/silver, \
		/obj/item/clothing/accessory/locket, \
		/obj/item/clothing/accessory/poncho/blue, \
		/obj/item/clothing/shoes/boots/cowboy, \
		/obj/item/clothing/suit/storage/toggle/bomber, \
		/obj/item/clothing/under/frontier, \
		/obj/item/clothing/under/overalls, \
		/obj/item/clothing/under/pants/classicjeans/ripped, \
		/obj/item/clothing/under/sl_suit), \
	LOOT_RARE(5, \
		/obj/item/storage/belt/utility/alien/full, \
		/obj/item/gun/projectile/revolver, \
		/obj/item/gun/projectile/sec, \
		/obj/item/gun/launcher/crossbow), \
	LOOT_DEPLETION(5, TRUE))

// Surface drone loot
// Since the actual drone loot is a bit stupid in how it is handled, this is a sparse and empty list with items I don't exactly want in it. But until we can get the proper items in . . .
DECLARE_LOOT(/loot/surface/drone, \
	LOOT_TABLE(\
		/obj/random/tool, \
		/obj/item/stack/cable_coil/random, \
		/obj/random/tank, \
		/obj/random/tech_supply/component, \
		LOOT_STACK(1, /obj/item/stack/material/steel, 25), \
		LOOT_STACK(1, /obj/item/stack/material/glass, 10), \
		LOOT_STACK(1, /obj/item/stack/material/plasteel, 5), \
		/obj/item/cell, \
		/obj/item/material/shard), \
	LOOT_UNCOMMON(20, \
		/obj/item/cell/high, \
		/obj/item/robot_parts/robot_component/actuator, \
		/obj/item/robot_parts/robot_component/armour, \
		/obj/item/robot_parts/robot_component/binary_communication_device, \
		/obj/item/robot_parts/robot_component/camera, \
		/obj/item/robot_parts/robot_component/diagnosis_unit, \
		/obj/item/robot_parts/robot_component/radio), \
	LOOT_RARE(5, \
		/obj/item/cell/super, \
		/obj/item/borg/upgrade/utility/restart, \
		/obj/item/borg/upgrade/advanced/jetpack, \
		/obj/item/borg/upgrade/restricted/tasercooler, \
		/obj/item/borg/upgrade/basic/syndicate, \
		/obj/item/borg/upgrade/basic/vtec), \
	LOOT_DEPLETION(5, FALSE))
