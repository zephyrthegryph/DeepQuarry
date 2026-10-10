/obj/effect/landmark
	name = "landmark"
	icon = 'icons/mob/screen1.dmi'
	icon_state = "x2"
	anchored = TRUE
	unacidable = TRUE
	simulated = FALSE
	invisibility = INVISIBILITY_MAXIMUM
	var/delete_me = FALSE

REGISTRY_MEMBERSHIP(/obj/effect/landmark, REGISTRY_LANDMARKS)

REGISTRY_MEMBERSHIP(/obj/effect/landmark, REGISTRY_LATEJOIN)

CAPABILITIES(/obj/effect/landmark)
	membership(joins = REGISTRY_LANDMARKS)
	map_resolver(GLOBAL_PROC_REF(resolve_landmark))

/// The map resolver of landmarks: a coordinate-only landmark (spawn points, event starts) becomes a
/// row in its coordinate registry and never an atom; costume landmarks roll their costume. Any
/// other landmark (one that stays, or a subtype with work of its own) is made normally.
/proc/resolve_landmark(atom/loc, path, list/varedits)
	if(ispath(path, /obj/effect/landmark/costume))
		loot_spawn(path, loc, varedits)
		return TRUE
	if(path != /obj/effect/landmark && !ispath(path, /obj/effect/landmark/start) && !ispath(path, /obj/effect/landmark/virtual_reality))
		return FALSE
	var/obj/effect/landmark/P = path
	var/list/registry = landmark_coordinate_registry(MAP_VAR(P, varedits, name))
	if(!registry)
		return FALSE
	var/turf/T = get_turf(loc)
	if(T)
		registry += T
	return TRUE

/// The coordinate registry a coordinate-only landmark name records into (the landmark itself is
/// never kept), or null for a landmark that stays an atom.
/proc/landmark_coordinate_registry(name)
	switch(name) //some of these are probably obsolete
		if("monkey")
			return GLOB.monkeystart
		if("start")
			return GLOB.newplayer_start
		if("JoinLateGateway")
			return GLOB.latejoin_gateway
		if("JoinLateStationGateway")
			return GLOB.latejoin_gatewaystation
		if("JoinLateSifPlains")
			return GLOB.latejoin_plainspath
		if("JoinLateFuelDepot")
			return GLOB.latejoin_fueldepot
		if("JoinLateTyrVillage")
			return GLOB.latejoin_tyrvillage
		if("JoinLateTheDark")
			return GLOB.latejoin_thedark
		if("JoinLateElevator")
			return GLOB.latejoin_elevator
		if("JoinLateCryo")
			return GLOB.latejoin_cryo
		if("JoinLateCyborg")
			return GLOB.latejoin_cyborg
		if("prisonwarp")
			return GLOB.prisonwarp
		if("prisonsecuritywarp")
			return GLOB.prisonsecuritywarp
		if("blobstart")
			return GLOB.blobstart
		if("xeno_spawn")
			return GLOB.xeno_spawn
		if("endgame_exit")
			return GLOB.endgame_safespawns
		if("bluespacerift")
			return GLOB.endgame_exits
		if("vinestart")
			return GLOB.vinestart
	return null

TYPE_TABLE_DECLARE(/obj/effect/landmark, landmark_tag_setup, null)

/obj/effect/landmark/Initialize(mapload)
	. = ..()
	tag = text("landmark*[]", name)
	invisibility = INVISIBILITY_ABSTRACT

	// A subtype placed with a coordinate-only name still records (it stays: its type has work).
	var/list/registry = landmark_coordinate_registry(name)
	if(registry)
		registry += loc
	switch(name)
		if("JoinLate") // Bit difference, since we need the spawn point to move.
			registry_join(REGISTRY_LATEJOIN, src)
			simulated = TRUE
			// always use this list with get_turf
		if("Holding Facility")
			GLOB.holdingfacility += loc
		if("tdome1")
			GLOB.tdome1 += loc
		if("tdome2")
			GLOB.tdome2 += loc
		if("tdomeadmin")
			GLOB.tdomeadmin += loc
		if("tdomeobserve")
			GLOB.tdomeobserve += loc
	switch(TYPE_TABLE_GET(src, landmark_tag_setup))
		if(/obj/effect/landmark/start)
			tag = "start*[name]"
		if(/obj/effect/landmark/virtual_reality)
			tag = "virtual_reality*[name]"

// Landmarks survive deletion unless flagged delete_me or forced.
/obj/effect/landmark/lifecycle_keep(force)
	return !delete_me && !force

/obj/effect/landmark/start
	name = "start"
	icon = 'icons/mob/screen1.dmi'
	icon_state = "x"
	anchored = TRUE

TYPE_TABLE(/obj/effect/landmark/start, landmark_tag_setup, /obj/effect/landmark/start)

/obj/effect/landmark/virtual_reality
	name = "virtual_reality"
	icon = 'icons/mob/screen1.dmi'
	icon_state = "x"
	anchored = TRUE

TYPE_TABLE(/obj/effect/landmark/virtual_reality, landmark_tag_setup, /obj/effect/landmark/virtual_reality)

/obj/effect/landmark/costume

// Costume spawners roll their costume at map time (resolve_landmark()); the base picks one.
CAPABILITIES(/obj/effect/landmark/costume)
	loot(table = list(loot_types(1, subtypesof(/obj/effect/landmark/costume))))
CAPABILITIES(/loot/costume/cueball)
	loot(table = list(/obj/item/clothing/head/cueball), chance = 30)
CAPABILITIES(/loot/costume/cyborg_mask)
	loot(table = list(/obj/item/clothing/mask/gas/cyborg), chance = 25)

/obj/effect/landmark/costume/chicken
CAPABILITIES(/obj/effect/landmark/costume/chicken)
	configure(loot(all = list(/obj/item/clothing/suit/chickensuit, /obj/item/clothing/head/chicken, /obj/item/reagent_containers/food/snacks/egg)))
/obj/effect/landmark/costume/gladiator
CAPABILITIES(/obj/effect/landmark/costume/gladiator)
	configure(loot(all = list(/obj/item/clothing/under/gladiator, /obj/item/clothing/head/helmet/gladiator)))
/obj/effect/landmark/costume/madscientist
CAPABILITIES(/obj/effect/landmark/costume/madscientist)
	configure(loot(
		all = list(
			/obj/item/clothing/under/suit_jacket/green,
			/obj/item/clothing/head/flatcap,
			/obj/item/clothing/suit/storage/toggle/labcoat/mad,
			/obj/item/clothing/glasses/gglasses)))
/obj/effect/landmark/costume/elpresidente
CAPABILITIES(/obj/effect/landmark/costume/elpresidente)
	configure(loot(
		all = list(
			/obj/item/clothing/under/suit_jacket/green,
			/obj/item/clothing/head/flatcap,
			/obj/item/clothing/mask/smokable/cigarette/cigar/havana,
			/obj/item/clothing/shoes/boots/jackboots)))
/obj/effect/landmark/costume/nyangirl
CAPABILITIES(/obj/effect/landmark/costume/nyangirl)
	configure(loot(all = list(/obj/item/clothing/under/schoolgirl, /obj/item/clothing/head/kitty)))
/obj/effect/landmark/costume/maid
CAPABILITIES(/obj/effect/landmark/costume/maid)
	configure(loot(
		all = list(
			/obj/item/clothing/under/skirt,
			loot_sub(1, list(/obj/item/clothing/head/beret, /obj/item/clothing/head/rabbitears)),
			/obj/item/clothing/glasses/sunglasses/blindfold)))
/obj/effect/landmark/costume/butler
CAPABILITIES(/obj/effect/landmark/costume/butler)
	configure(loot(all = list(/obj/item/clothing/accessory/wcoat, /obj/item/clothing/under/suit_jacket, /obj/item/clothing/head/that)))
/obj/effect/landmark/costume/scratch
CAPABILITIES(/obj/effect/landmark/costume/scratch)
	configure(loot(all = list(/obj/item/clothing/gloves/white, /obj/item/clothing/shoes/white, /obj/item/clothing/under/scratch, /loot/costume/cueball)))
/obj/effect/landmark/costume/highlander
CAPABILITIES(/obj/effect/landmark/costume/highlander)
	configure(loot(all = list(/obj/item/clothing/under/kilt, /obj/item/clothing/head/beret)))
/obj/effect/landmark/costume/prig
CAPABILITIES(/obj/effect/landmark/costume/prig)
	configure(loot(
		all = list(
			/obj/item/clothing/accessory/wcoat,
			/obj/item/clothing/glasses/monocle,
			loot_sub(1, list(/obj/item/clothing/head/bowler, /obj/item/clothing/head/that)),
			/obj/item/clothing/shoes/black,
			/obj/item/cane,
			/obj/item/clothing/under/sl_suit,
			/obj/item/clothing/mask/fakemoustache)))
/obj/effect/landmark/costume/plaguedoctor
CAPABILITIES(/obj/effect/landmark/costume/plaguedoctor)
	configure(loot(all = list(/obj/item/clothing/suit/bio_suit/plaguedoctorsuit, /obj/item/clothing/head/plaguedoctorhat)))
/obj/effect/landmark/costume/nightowl
CAPABILITIES(/obj/effect/landmark/costume/nightowl)
	configure(loot(all = list(/obj/item/clothing/under/owl, /obj/item/clothing/mask/gas/owl_mask)))
/obj/effect/landmark/costume/waiter
CAPABILITIES(/obj/effect/landmark/costume/waiter)
	configure(loot(
		all = list(
			/obj/item/clothing/under/waiter,
			loot_sub(1, list(/obj/item/clothing/head/kitty, /obj/item/clothing/head/rabbitears)),
			/obj/item/clothing/suit/storage/apron)))
/obj/effect/landmark/costume/pirate
CAPABILITIES(/obj/effect/landmark/costume/pirate)
	configure(loot(
		all = list(
			/obj/item/clothing/under/pirate,
			/obj/item/clothing/suit/pirate,
			loot_sub(1, list(/obj/item/clothing/head/pirate, /obj/item/clothing/head/bandana)),
			/obj/item/clothing/glasses/eyepatch)))
/obj/effect/landmark/costume/commie
CAPABILITIES(/obj/effect/landmark/costume/commie)
	configure(loot(all = list(/obj/item/clothing/under/soviet, /obj/item/clothing/head/ushanka)))
/obj/effect/landmark/costume/imperium_monk
CAPABILITIES(/obj/effect/landmark/costume/imperium_monk)
	configure(loot(all = list(/obj/item/clothing/suit/imperium_monk, /loot/costume/cyborg_mask)))
/obj/effect/landmark/costume/holiday_priest
CAPABILITIES(/obj/effect/landmark/costume/holiday_priest)
	configure(loot(all = list(/obj/item/clothing/suit/holidaypriest)))
/obj/effect/landmark/costume/marisawizard/fake
CAPABILITIES(/obj/effect/landmark/costume/marisawizard/fake)
	configure(loot(all = list(/obj/item/clothing/head/wizard/marisa/fake, /obj/item/clothing/suit/wizrobe/marisa/fake)))
/obj/effect/landmark/costume/cutewitch
CAPABILITIES(/obj/effect/landmark/costume/cutewitch)
	configure(loot(all = list(/obj/item/clothing/under/sundress, /obj/item/clothing/head/witchwig, /obj/item/staff/broom)))
/obj/effect/landmark/costume/fakewizard
CAPABILITIES(/obj/effect/landmark/costume/fakewizard)
	configure(loot(all = list(/obj/item/clothing/suit/wizrobe/fake, /obj/item/clothing/head/wizard/fake, /obj/item/staff)))
/obj/effect/landmark/costume/sexyclown
CAPABILITIES(/obj/effect/landmark/costume/sexyclown)
	configure(loot(all = list(/obj/item/clothing/mask/gas/sexyclown, /obj/item/clothing/under/sexyclown)))
/obj/effect/landmark/costume/sexymime
CAPABILITIES(/obj/effect/landmark/costume/sexymime)
	configure(loot(all = list(/obj/item/clothing/mask/gas/sexymime, /obj/item/clothing/under/sexymime)))

/// Marks the bottom left of the testing zone.
/// In landmarks.dm and not unit_test.dm so it is always active in the mapping tools.
/obj/effect/landmark/unit_test_bottom_left
	name = "unit test zone bottom left"

/// Marks the top right of the testing zone.
/// In landmarks.dm and not unit_test.dm so it is always active in the mapping tools.
/obj/effect/landmark/unit_test_top_right
	name = "unit test zone top right"

/obj/effect/landmark
	var/abductor = 0

/obj/effect/landmark/wildlife
	name = "wildlife"
	var/wildlife_type = 2		//1 for water, 2 for land; thats all for now

