/obj/structure/closet/syndicate
	name = "armory closet"
	desc = "Why is this here?"
	closet_appearance = /datum/decl/closet_appearance/tactical/alt

/obj/structure/closet/syndicate/personal
	desc = "It's a storage unit for operative gear."

	starts_with = list(
		/obj/item/tank/jetpack/oxygen,
		/obj/item/clothing/mask/gas/syndicate,
		/obj/item/clothing/under/syndicate,
		/obj/item/clothing/head/helmet/space/void/merc,
		/obj/item/clothing/suit/space/void/merc,
		/obj/item/tool/crowbar/red,
		/obj/item/cell/high,
		/obj/item/card/id/syndicate,
		/obj/item/multitool,
		/obj/item/shield/energy,
		/obj/item/clothing/shoes/magboots)


/obj/structure/closet/syndicate/suit
	desc = "It's a storage unit for voidsuits."

	starts_with = list(
		/obj/item/tank/jetpack/oxygen,
		/obj/item/clothing/shoes/magboots,
		/obj/item/clothing/suit/space/void/merc,
		/obj/item/clothing/mask/gas/syndicate,
		/obj/item/clothing/head/helmet/space/void/merc)


/obj/structure/closet/syndicate/nuclear
	desc = "It's a storage unit for nuclear-operative gear."

	starts_with = list(
	/obj/item/ammo_magazine/m10mm = 5,
	/obj/item/storage/box/handcuffs,
	/obj/item/storage/box/flashbangs,
	/obj/item/gun/energy/gun = 5,
	/obj/item/pinpointer/nukeop = 5,
	/obj/item/pda/syndicate,
	/obj/item/radio/uplink)

/obj/structure/closet/syndicate/resources
	desc = "An old, dusty locker."

CAPABILITIES(/obj/structure/closet/syndicate/resources)
	initial_contents(PROC_REF(roll_stash))

/// Rolled contents (initial_contents()): one roll of 1-50 decides how deep into the stash list it goes. A mapper who filled the locker
/// keeps their contents alone.
/obj/structure/closet/syndicate/resources/proc/roll_stash(datum/roller/R)
	if(length(starts_with))
		return null
	var/pickednum = R.number(1, 50)
	if(pickednum == 1) // Sad trombone
		return list(make(/obj/item/paper, name = "IOU", info = "Sorry man, we needed the money so we sold your stash. It's ok, we'll double our money for sure this time!"))
	. = list()
	// minimum depth, stack type, common (30-50) or rare (5-20)
	for(var/list/row in list(list(2, /obj/item/stack/material/steel, TRUE), list(5, /obj/item/stack/material/glass, TRUE),
			list(10, /obj/item/stack/material/plasteel, TRUE), list(15, /obj/item/stack/material/phoron, FALSE),
			list(20, /obj/item/stack/material/silver, FALSE), list(30, /obj/item/stack/material/gold, FALSE),
			list(40, /obj/item/stack/material/uranium, FALSE), list(45, /obj/item/stack/material/diamond, FALSE)))
		if(pickednum >= row[1])
			var/stack_type = row[2]
			. += new stack_type(null, row[3] ? R.number(30, 50) : R.number(5, 20))
	if(pickednum == 50) // You hit the jackpot!
		. += /obj/item/tank/jetpack/carbondioxide

/obj/structure/closet/syndicate/resources/everything
	desc = "It's an emergency storage closet for repairs."

CAPABILITIES(/obj/structure/closet/syndicate/resources/everything)
	initial_contents(/obj/item/stack/material/steel, count = 2, args = list(-1))
	initial_contents(/obj/item/stack/material/glass, count = 2, args = list(-1))
	initial_contents(/obj/item/stack/material/gold, count = 2, args = list(-1))
	initial_contents(/obj/item/stack/material/silver, count = 2, args = list(-1))
	initial_contents(/obj/item/stack/material/phoron, count = 2, args = list(-1))
	initial_contents(/obj/item/stack/material/uranium, count = 2, args = list(-1))
	initial_contents(/obj/item/stack/material/diamond, count = 2, args = list(-1))
	initial_contents(/obj/item/stack/material/plasteel, count = 2, args = list(-1))
	initial_contents(/obj/item/stack/rods, count = 2, args = list(-1))
