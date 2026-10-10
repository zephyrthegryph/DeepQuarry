//added by cael from old bs12
//not sure if there's an immediate place for secure wall lockers, but i'm sure the players will think of something

/obj/structure/closet/walllocker
	desc = "A wall mounted storage locker."
	name = "wall locker"
	icon = 'icons/obj/closets/bases/wall.dmi'
	closet_appearance = /datum/decl/closet_appearance/wall
	density = FALSE
	anchored = TRUE
	store_mobs = 0
	wall_mounted = 1

	open_sound = SFX_MACHINES_CLICK
	close_sound = SFX_MACHINES_CLICK

//spawns 2 sets of breathmask, emergency oxy tank and crowbar

/obj/structure/closet/walllocker/emerglocker
	name = "emergency locker"
	desc = "A wall mounted locker with emergency supplies."
	var/static/list/spawnitems = list(/obj/item/tank/emergency/oxygen,/obj/item/clothing/mask/breath,/obj/item/tool/crowbar/red,/obj/item/flashlight/flare,)
	var/amount = 2 // spawns each items X times.
	closet_appearance = /datum/decl/closet_appearance/wall/emergency

MSG_DEF_SELF(emerglocker/empty, "It's empty.")
MSG_DEF(emerglocker/taken, "You take out some items from %T%.", "%U% takes some items out of %T%.")

// An emergency locker hands out its supplies (twice) instead of opening: a hand takes them, and nothing is put in or stuffed in.
CAPABILITIES(/obj/structure/closet/walllocker/emerglocker)
	without("door")
	without("stuff")
	without("stuff_grab")
	without("set_down")
	without("empty_basket")
	op("take_supplies", hand(), label("Take supplies"), when(PROC_REF(actor_is_no_ai)), needs(req(PROC_REF(has_supplies))),
		then(PROC_REF(supplies_taken)), says(MSG(emerglocker/taken)))

/// The AI cannot reach in.
/obj/structure/closet/walllocker/emerglocker/proc/actor_is_no_ai(datum/act/op/A)
	return !isAI(A.actor)

/obj/structure/closet/walllocker/emerglocker/proc/has_supplies(datum/act/A)
	return (amount > 0) ? null : /datum/msg/emerglocker/empty // ALLOW(reads): how many sets are left is read when the entry is offered and when it is picked


/// A set of supplies comes out onto the tile.
/obj/structure/closet/walllocker/emerglocker/proc/supplies_taken(datum/act/op/A)
	for(var/path in spawnitems)
		new path(src.loc)
	amount--
	return OP_OK

/obj/structure/closet/walllocker/emerglocker/north
	pixel_y = 32
	dir = SOUTH

/obj/structure/closet/walllocker/emerglocker/south
	pixel_y = -32
	dir = NORTH

/obj/structure/closet/walllocker/emerglocker/west
	pixel_x = -32
	dir = WEST

/obj/structure/closet/walllocker/emerglocker/east
	pixel_x = 32
	dir = EAST

/obj/structure/closet/walllocker/medical
	name = "first-aid closet"
	desc = "It's a wall-mounted storage unit for first aid supplies."
	closet_appearance = /datum/decl/closet_appearance/wall/medical

/obj/structure/closet/walllocker/medical/north
	pixel_y = 32
	dir = SOUTH

/obj/structure/closet/walllocker/medical/south
	pixel_y = -32
	dir = NORTH

/obj/structure/closet/walllocker/medical/west
	pixel_x = -32
	dir = WEST

/obj/structure/closet/walllocker/medical/east
	pixel_x = 32
	dir = EAST

/obj/structure/closet/walllocker/wooden
	name = "wooden cabinet"
	desc = "A wall mounted storage cabinet."
	closet_appearance = /datum/decl/closet_appearance/wall_double/wooden

/obj/structure/closet/walllocker/wooden/north
	pixel_y = 32
	dir = SOUTH

/obj/structure/closet/walllocker/wooden/south
	pixel_y = -32
	dir = NORTH

/obj/structure/closet/walllocker/wooden/west
	pixel_x = -32
	dir = WEST

/obj/structure/closet/walllocker/wooden/east
	pixel_x = 32
	dir = EAST

//double-size "cabinet" lockers, from Killian
/obj/structure/closet/walllocker_double
	desc = "A wall mounted storage cabinet."
	name = "wall cabinet"
	icon = 'icons/obj/closets/bases/wall_double.dmi'
	closet_appearance = /datum/decl/closet_appearance/wall_double
	density = FALSE
	anchored = TRUE
	store_mobs = 0
	wall_mounted = 1
	plane = TURF_PLANE
	layer = ABOVE_TURF_LAYER

	open_sound = SFX_MACHINES_CLICK
	close_sound = SFX_MACHINES_CLICK

/obj/structure/closet/walllocker_double/north
	pixel_y = 32
	dir = SOUTH

/obj/structure/closet/walllocker_double/south
	pixel_y = -32
	dir = NORTH

/obj/structure/closet/walllocker_double/west
	pixel_x = -32
	dir = WEST

/obj/structure/closet/walllocker_double/east
	pixel_x = 32
	dir = EAST

/obj/structure/closet/walllocker_double/kitchen
	desc = "A wall mounted storage cabinet, for the kitchen. Now where's the flour gone..?"
	name = "kitchen cabinet"
	icon = 'icons/obj/closets/bases/wall_double.dmi'
	closet_appearance = /datum/decl/closet_appearance/wall_double/kitchen
	density = FALSE
	anchored = TRUE

/obj/structure/closet/walllocker_double/kitchen/north
	pixel_y = 32
	dir = SOUTH

/obj/structure/closet/walllocker_double/kitchen/south
	pixel_y = -32
	dir = NORTH

/obj/structure/closet/walllocker_double/kitchen/west
	pixel_x = -32
	dir = WEST

/obj/structure/closet/walllocker_double/kitchen/east
	pixel_x = 32
	dir = EAST

/obj/structure/closet/walllocker_double/medical
	name = "medical cabinet"
	desc = "A wall mounted medical supply cabinet. Probably full of drugs!"	//not actually full of drugs, sorry!
	closet_appearance = /datum/decl/closet_appearance/wall_double/medical

/obj/structure/closet/walllocker_double/medical/north
	pixel_y = 32
	dir = SOUTH

/obj/structure/closet/walllocker_double/medical/south
	pixel_y = -32
	dir = NORTH

/obj/structure/closet/walllocker_double/medical/west
	pixel_x = -32
	dir = WEST

/obj/structure/closet/walllocker_double/medical/east
	pixel_x = 32
	dir = EAST

/obj/structure/closet/walllocker_double/emergency_engi
	name = "emergency supplies cabinet"
	desc = "A wall mounted cabinet. Seemingly has cool stuff for 'emergency use only'."
	closet_appearance = /datum/decl/closet_appearance/wall_double/emergency_engi

	starts_with = list(
		/obj/item/clothing/mask/breath = 2,
		/obj/item/tank/emergency/oxygen/engi = 2,
		/obj/item/storage/briefcase/inflatable,
		/obj/item/radio = 3)

/obj/structure/closet/walllocker_double/emergency_engi/north
	pixel_y = 32
	dir = SOUTH

/obj/structure/closet/walllocker_double/emergency_engi/south
	pixel_y = -32
	dir = NORTH

/obj/structure/closet/walllocker_double/emergency_engi/west
	pixel_x = -32
	dir = WEST

/obj/structure/closet/walllocker_double/emergency_engi/east
	pixel_x = 32
	dir = EAST

/obj/structure/closet/walllocker_double/hydrant
	name = "fire-safety closet"
	desc = "It's a storage cabinet packed with fire-fighting supplies."
	closet_appearance = /datum/decl/closet_appearance/wall_double/fire_safety

	starts_with = list(
		/obj/item/clothing/suit/fire,
		/obj/item/clothing/mask/gas/clear,
		/obj/item/flashlight,
		/obj/item/tank/oxygen/red,
		/obj/item/extinguisher,
		/obj/item/clothing/head/hardhat/red)

/obj/structure/closet/walllocker_double/hydrant/north
	pixel_y = 32
	dir = SOUTH

/obj/structure/closet/walllocker_double/hydrant/south
	pixel_y = -32
	dir = NORTH

/obj/structure/closet/walllocker_double/hydrant/west
	pixel_x = -32
	dir = WEST

/obj/structure/closet/walllocker_double/hydrant/east
	pixel_x = 32
	dir = EAST

/obj/structure/closet/walllocker_double/survival
	desc = "A wall mounted storage cabinet. It contains a small amount of emergency supplies for wilderness survival, but they probably won't last very long."
	name = "emergency survival wall cabinet"
	icon = 'icons/obj/closets/bases/wall_double.dmi'
	closet_appearance = /datum/decl/closet_appearance/wall_double/survival
	density = FALSE
	anchored = TRUE
	store_mobs = 0
	wall_mounted = 1
	plane = TURF_PLANE
	layer = ABOVE_TURF_LAYER

	starts_with = list(
		/obj/item/clothing/suit/space/emergency,
		/obj/item/clothing/head/helmet/space/emergency,
		/obj/item/clothing/mask/breath,
		/obj/item/tank/oxygen,
		/obj/item/suit_cooling_unit/emergency,
		/obj/item/gps,
		/obj/item/material/knife/tacknife/survival,
		/obj/random/mre,
		/obj/item/flashlight/color/yellow,
		/obj/item/flashlight/flare,
		/obj/item/reagent_containers/food/drinks/cans/waterbottle)

/obj/structure/closet/walllocker_double/survival/north
	pixel_y = 32
	dir = SOUTH

/obj/structure/closet/walllocker_double/survival/south
	pixel_y = -32
	dir = NORTH

/obj/structure/closet/walllocker_double/survival/west
	pixel_x = -32
	dir = WEST

/obj/structure/closet/walllocker_double/survival/east
	pixel_x = 32
	dir = EAST

/obj/structure/closet/walllocker_double/security
	name = "security cabinet"
	desc = "A wall mounted cabinet. This one is suspiciously red."
	closet_appearance = /datum/decl/closet_appearance/wall_double/security

/obj/structure/closet/walllocker_double/security/north
	pixel_y = 32
	dir = SOUTH

/obj/structure/closet/walllocker_double/security/south
	pixel_y = -32
	dir = NORTH

/obj/structure/closet/walllocker_double/security/west
	pixel_x = -32
	dir = WEST

/obj/structure/closet/walllocker_double/security/east
	pixel_x = 32
	dir = EAST

/obj/structure/closet/walllocker_double/misc_civ
	closet_appearance = /datum/decl/closet_appearance/wall_double/gaming

/obj/structure/closet/walllocker_double/misc_civ/north
	pixel_y = 32
	dir = SOUTH

/obj/structure/closet/walllocker_double/misc_civ/south
	pixel_y = -32
	dir = NORTH

/obj/structure/closet/walllocker_double/misc_civ/west
	pixel_x = -32
	dir = WEST

/obj/structure/closet/walllocker_double/misc_civ/east
	pixel_x = 32
	dir = EAST

/obj/structure/closet/walllocker_double/generic_civ
	closet_appearance = /datum/decl/closet_appearance/wall_double/generic_civ

/obj/structure/closet/walllocker_double/generic_civ/north
	pixel_y = 32
	dir = SOUTH

/obj/structure/closet/walllocker_double/generic_civ/south
	pixel_y = -32
	dir = NORTH

/obj/structure/closet/walllocker_double/generic_civ/west
	pixel_x = -32
	dir = WEST

/obj/structure/closet/walllocker_double/generic_civ/east
	pixel_x = 32
	dir = EAST

/obj/structure/closet/walllocker_double/casino
	closet_appearance = /datum/decl/closet_appearance/wall_double/casino

/obj/structure/closet/walllocker_double/casino/north
	pixel_y = 32
	dir = SOUTH

/obj/structure/closet/walllocker_double/casino/south
	pixel_y = -32
	dir = NORTH

/obj/structure/closet/walllocker_double/casino/west
	pixel_x = -32
	dir = WEST

/obj/structure/closet/walllocker_double/casino/east
	pixel_x = 32
	dir = EAST

/obj/structure/closet/walllocker_double/cargo
	desc = "A wall mounted cabinet. This one is in cargo colors."
	closet_appearance = /datum/decl/closet_appearance/wall_double/cargo

/obj/structure/closet/walllocker_double/cargo/north
	pixel_y = 32
	dir = SOUTH

/obj/structure/closet/walllocker_double/cargo/south
	pixel_y = -32
	dir = NORTH

/obj/structure/closet/walllocker_double/cargo/west
	pixel_x = -32
	dir = WEST

/obj/structure/closet/walllocker_double/cargo/east
	pixel_x = 32
	dir = EAST

/obj/structure/closet/walllocker_double/science
	desc = "A wall mounted cabinet. This one is in research colors."
	closet_appearance = /datum/decl/closet_appearance/wall_double/science

/obj/structure/closet/walllocker_double/science/north
	pixel_y = 32
	dir = SOUTH

/obj/structure/closet/walllocker_double/science/south
	pixel_y = -32
	dir = NORTH

/obj/structure/closet/walllocker_double/science/west
	pixel_x = -32
	dir = WEST

/obj/structure/closet/walllocker_double/science/east
	pixel_x = 32
	dir = EAST

/obj/structure/closet/walllocker_double/command
	desc = "A wall mounted cabinet. This one is in command colors."
	closet_appearance = /datum/decl/closet_appearance/wall_double/command

/obj/structure/closet/walllocker_double/command/north
	pixel_y = 32
	dir = SOUTH

/obj/structure/closet/walllocker_double/command/south
	pixel_y = -32
	dir = NORTH

/obj/structure/closet/walllocker_double/command/west
	pixel_x = -32
	dir = WEST

/obj/structure/closet/walllocker_double/command/east
	pixel_x = 32
	dir = EAST

/obj/structure/closet/walllocker_double/command/ce
	closet_appearance = /datum/decl/closet_appearance/wall_double/ce

/obj/structure/closet/walllocker_double/command/cmo
	closet_appearance = /datum/decl/closet_appearance/wall_double/cmo

/obj/structure/closet/walllocker_double/command/rd
	closet_appearance = /datum/decl/closet_appearance/wall_double/rd

/obj/structure/closet/walllocker_double/command/hos
	closet_appearance = /datum/decl/closet_appearance/wall_double/hos

/obj/structure/closet/walllocker_double/command/iaa
	closet_appearance = /datum/decl/closet_appearance/wall_double/iaa

/obj/structure/closet/walllocker_double/engineering
	desc = "A wall mounted cabinet. This one is in engineering colors."
	closet_appearance = /datum/decl/closet_appearance/wall_double/engineering

/obj/structure/closet/walllocker_double/engineering/north
	pixel_y = 32
	dir = SOUTH

/obj/structure/closet/walllocker_double/engineering/south
	pixel_y = -32
	dir = NORTH

/obj/structure/closet/walllocker_double/engineering/west
	pixel_x = -32
	dir = WEST

/obj/structure/closet/walllocker_double/engineering/east
	pixel_x = 32
	dir = EAST
