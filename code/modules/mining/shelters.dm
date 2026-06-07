/datum/map_template/shelter
	var/superpose = FALSE
	var/shuttle = FALSE

// Subtype to mark maps for use with the superpose capsule. This is mostly to prevent automatic additions from upstream changes.
/datum/map_template/shelter/superpose
	superpose = TRUE
	name = "ERROR: string 'name' cannot be null!"
	description = "ERROR: string 'description' cannot be null!"
	mappath = null

/* Does not spawn properly
/datum/map_template/shelter/superpose/CrashedInfestedShip
	shelter_id = "CrashedInfestedShip"
	mappath = "maps/submaps/shelters/CrashedInfestedShip-56x25.dmm"
	name = "Crashed infested ship."
	description = "A large alien ship that is heavily damaged, there is signs of xeno infestation."
*/

/* Does not spawn properly
/datum/map_template/shelter/superpose/CrashedQurantineShip
	shelter_id = "CrashedQurantineShip"
	mappath = "maps/submaps/shelters/CrashedQurantineShip-25x25.dmm"
	name = "Crashed Qurantine Ship."
	description = "A white medical ship that is heavily damaged, there is signs of a viral outbreak."
*/
/datum/map_template/shelter/superpose/CultShip
	shelter_id = "CultShip"
	mappath = "maps/submaps/shelters/CultShip-28x17.dmm"
	name = "Cultist ship."
	description = "A medium size cult themed ship, it has some basic cultist gear."

/datum/map_template/shelter/superpose/dragoncave
	shelter_id = "DragonCave"
	mappath = "maps/submaps/shelters/DragonCave-18x18.dmm"
	name = "Dragon Cave"
	description = "A small cave with treasure featuring a tucked away hotspring."

/datum/map_template/shelter/superpose/DemonPool
	shelter_id = "DemonPool"
	mappath = "maps/submaps/shelters/DemonPool-21x21.dmm"
	name = "Demon pool."
	description = "A large redspace corruption with lava, flesh tiles and a small cultist room in the middle."

/datum/map_template/shelter/superpose/Dinner
	shelter_id = "Dinner"
	mappath = "maps/submaps/shelters/Dinner-25x25.dmm"
	name = "Local diner."
	description = "A medium size diner with all kitchen appliances and food."

/datum/map_template/shelter/superpose/ExplorerHome
	shelter_id = "ExplorerHome"
	mappath = "maps/submaps/shelters/ExplorerHome-17x20.dmm"
	name = "Explorer home."
	description = "A small wooden home with various hunting prizes and the basics to survive in the wilderness."

/datum/map_template/shelter/superpose/Farm
	shelter_id = "Farm"
	mappath = "maps/submaps/shelters/Farm-32x32.dmm"
	name = "Farm."
	description = "A medium size farm with all the needs to grow food!"

/datum/map_template/shelter/superpose/FieldLab
	shelter_id = "FieldLab"
	mappath = "maps/submaps/shelters/FieldLab-20x20.dmm"
	name = "Field laboratory."
	description = "A compact laboratory with various science machines and equipment."

/datum/map_template/shelter/superpose/HellCave
	shelter_id = "HellCave"
	mappath = "maps/submaps/shelters/HellCave-40x25.dmm"
	name = "Hell cave."
	description = "A small cave corrupted by redspace, filled with various cultist items."

/datum/map_template/shelter/superpose/HydroCave
	shelter_id = "HydroCave"
	mappath = "maps/submaps/shelters/HydroCave-40x40.dmm"
	name = "Hydroponics cave."
	description = "A burried hydroponics facility with various living quarters needs and equipment."

/* Does not spawn properly/Too OP for outsider use
/datum/map_template/shelter/superpose/LargeAlienShip
	shelter_id = "LargeAlienShip"
	mappath = "maps/submaps/shelters/LargeAlienShip-57x25.dmm"
	name = "Large alien ship."
	description = "A large alien ship filled with various alien machines and items."
*/

/datum/map_template/shelter/superpose/LoneHome
	shelter_id = "LoneHome"
	mappath = "maps/submaps/shelters/LoneHome-18x22.dmm"
	name = "Lonely home."
	description = "An old very worn down wooden house, with enough materials and tools to refurnish and repair it."

/datum/map_template/shelter/superpose/LoneHomeclean
	shelter_id = "LoneHomeclean"
	mappath = "maps/submaps/shelters/LoneHomeclean-18x22.dmm"
	name = "Lonely home. (Repaired)"


/datum/map_template/shelter/superpose/MechFabShip
	shelter_id = "MechFabShip"
	mappath = "maps/submaps/shelters/MechFabShip-27x24.dmm"
	name = "Mech fabrication ship."
	description = "A medium size ship equiped with mech fabrication machines."

/datum/map_template/shelter/superpose/MechStorageFab
	shelter_id = "MechStorageFab"
	mappath = "maps/submaps/shelters/MechStorageFab-32x24.dmm"
	name = "Mech storage facility."
	description = "An old abandoned mech fabrication facility, most of the facility seems functional."

/* Does not spawn properly/too OP for outsider use
/datum/map_template/shelter/superpose/MercShip
	shelter_id = "MercShip"
	mappath = "maps/submaps/shelters/MercShip-57x25.dmm"
	name = "Mercenary ship."
	description = "A old mercenery ship filled with various trading goods."
*/

/datum/map_template/shelter/superpose/MethLab
	shelter_id = "MethLab"
	mappath = "maps/submaps/shelters/MethLab-20x20.dmm"
	name = "Meth laboratory."
	description = "A old worn down chemical lab used to produce illegal goods."

/datum/map_template/shelter/superpose/OldHotel
	shelter_id = "OldHotel"
	mappath = "maps/submaps/shelters/OldHotel-25x25.dmm"
	name = "Old hotel."
	description = "An old worn down wooden hotel, heavily damaged but with enough materials to patch it up."

/datum/map_template/shelter/superpose/NewHotel
	shelter_id = "NewHotel"
	mappath = "maps/submaps/shelters/NewHotel-18x22.dmm"
	name = "New Hotel."
	description = "An new not-worn down wooden hotel, not heavily damaged but with enough materials to do whatever."
/* Commented out due to poor implemantation, might be re-added as an outsider OM object.
/datum/map_template/shelter/superpose/ScienceShip
	shelter_id = "ScienceShip"
	mappath = "maps/submaps/shelters/ScienceShip-25x33.dmm"
	name = "Science ship."
	description = "An expedition science ship with all the needs to host a small team."
*/
/datum/map_template/shelter/superpose/SmallCombatShip
	shelter_id = "SmallCombatShip"
	mappath = "maps/submaps/shelters/SmallCombatShip-9x11.dmm"
	name = "Small combat ship."
	description = "A small combat ship with the bare minimum needs for survival."

/datum/map_template/shelter/superpose/SurvivalBarracks
	shelter_id = "SurvivalBarracks"
	mappath = "maps/submaps/shelters/SurvivalBarracks-11x11.dmm"
	name = "Survival barracks."
	description = "NT patented living quarters survival pod, all the needs to host 4 crew-mates."

/datum/map_template/shelter/superpose/SurvivalCargo
	shelter_id = "SurvivalCargo"
	mappath = "maps/submaps/shelters/SurvivalCargo-11x11.dmm"
	name = "Survival cargo dep."
	description = "NT patented cargo department survival pod, loaded with mining, crates and cargo gear."

/datum/map_template/shelter/superpose/SurvivalDIY_11x11
	shelter_id = "SurvivalDIY_11x11"
	mappath = "maps/submaps/shelters/SurvivalDIY-11x11.dmm"
	name = "Survival DIY large."
	description = "NT patented Do-it-yourself survival pod, a large inflatable building filled with building materials. It even has a RCD and a cargo vehicle."

/datum/map_template/shelter/superpose/SurvivalDIYlite_11x11
	shelter_id = "SurvivalDIY_11x11lite"
	mappath = "maps/submaps/shelters/SurvivalDIYlite-11x11.dmm"
	name = "Survival DIY large. (Lite version)"
	description = "NT patented Do-it-yourself survival pod, a much more stripped down of the existing large pod for more construction freedom."

/datum/map_template/shelter/superpose/SurvivalDIY_7x7
	shelter_id = "SurvivalDIY_7x7"
	mappath = "maps/submaps/shelters/SurvivalDIY-7x7.dmm"
	name = "Survival DIY medium."
	description = "NT patented Do-it-yourself survival pod, a medium inflatable building filled with building materials. It even has a RCD and a quad-bike."

/datum/map_template/shelter/superpose/SurvivalDIY_9x9
	shelter_id = "SurvivalDIY_9x9"
	mappath = "maps/submaps/shelters/SurvivalDIY-9x9.dmm"
	name = "Survival DIY small."
	description = "NT patented Do-it-yourself survival pod, a small inflatable building filled with building materials. It even has a RCD."

/datum/map_template/shelter/superpose/SurvivalDinner
	shelter_id = "SurvivalDinner"
	mappath = "maps/submaps/shelters/SurvivalDinner-11x11.dmm"
	name = "Survival mess hall."
	description = "NT patented mess hall and kitchen survival pod, it has all a kitchen requires to cook food. Bathroom included!"

/datum/map_template/shelter/superpose/SurvivalEngineering
	shelter_id = "SurvivalEngineering"
	mappath = "maps/submaps/shelters/SurvivalEngineering-9x9.dmm"
	name = "Survival engineering dep."
	description = "NT patented engineering survival pod, loaded with tools, machines and materials to patch and fix any facility."

/datum/map_template/shelter/superpose/SurvivalHome
	shelter_id = "SurvivalHome"
	mappath = "maps/submaps/shelters/SurvivalHome-9x9.dmm"
	name = "Survival home pod."
	description = "A medium survival pod that can host a small team, has some basic survival gear."

/datum/map_template/shelter/superpose/SurvivalHydro
	shelter_id = "SurvivalHydro"
	mappath = "maps/submaps/shelters/SurvivalHydro-9x9.dmm"
	name = "Survival hydroponics bay. "
	description = "NT patented hydroponics survival pod, loaded with everything you need to start growing food."

/datum/map_template/shelter/superpose/SurvivalJanitor
	shelter_id = "SurvivalJanitor"
	mappath = "maps/submaps/shelters/SurvivalJanitor-7x7.dmm"
	name = "Survival janitor pod."
	description = "NT patented janitor survival pod, loaded with enough cleaning supplies to clean any mess."

/datum/map_template/shelter/superpose/SurvivalLeisure
	shelter_id = "SurvivalLeisure"
	mappath = "maps/submaps/shelters/SurvivalLeisure-9x9.dmm"
	name = "Survival leisure pod."
	description = "NT patented leisure survival pod, loaded with various recreational goods to stave off boredom."

/datum/map_template/shelter/superpose/SurvivalLuxuryBar
	shelter_id = "SurvivalLuxuryBar"
	mappath = "maps/submaps/shelters/SurvivalLuxuryBar-11x11.dmm"
	name = "Survival luxury bar."
	description = "A luxurious bar pod, includes a large selection of liquors, bathroom and even a strip room!"

/datum/map_template/shelter/superpose/SurvivalLuxuryHome
	shelter_id = "SurvivalLuxuryHome"
	mappath = "maps/submaps/shelters/SurvivalLuxuryHome-11x11.dmm"
	name = "Survival luxury home."
	description = "A luxurious pod filled with various home amenities, is a home away from home!"

/datum/map_template/shelter/superpose/SurvivalMedical
	shelter_id = "SurvivalMedical"
	mappath = "maps/submaps/shelters/SurvivalMedical-9x9.dmm"
	name = "Survival medical dep."
	description = "NT patented medical survival pod, loaded with medical equipment, scanner, sleeper and a surgery table."

/datum/map_template/shelter/superpose/SurvivalPool
	shelter_id = "SurvivalPool"
	mappath = "maps/submaps/shelters/SurvivalPool-11x11.dmm"
	name = "Survival pool pod."
	description = "NT patented leisure pool survival pod, a leisure structure for crew to workout and relax."

/datum/map_template/shelter/superpose/SurvivalQuarters
	shelter_id = "SurvivalQuarters"
	mappath = "maps/submaps/shelters/SurvivalQuarters-9x9.dmm"
	name = "Survival living quarters."
	description = "NT patented survival quarters pod, loaded with survival equipment and enough beds for 4 crewmates."
/* Commented out due to powergame
/datum/map_template/shelter/superpose/SurvivalScience
	shelter_id = "SurvivalScience"
	mappath = "maps/submaps/shelters/SurvivalScience-9x9.dmm"
	name = "Survival science dep."
	description = "NT patented science survival pod, loaded with research terminals, mech fabricator, autolathe and everything to do field research."
*/
/datum/map_template/shelter/superpose/SurvivalSecurity
	shelter_id = "SurvivalSecurity"
	mappath = "maps/submaps/shelters/SurvivalSecurity-9x9.dmm"
	name = "Survival security dep."
	description = "NT patented security survival pod, a high security brig with and some security equipment."

/datum/map_template/shelter/superpose/TinyCombatShip
	shelter_id = "TinyCombatShip"
	mappath = "maps/submaps/shelters/TinyCombatShip-9x7.dmm"
	name = "Tiny combat ship."
	description = "A very small combat ship with the bare minimum of survival gear."

/datum/map_template/shelter/superpose/TradingShip
	shelter_id = "TradingShip"
	mappath = "maps/submaps/shelters/TradingShip-40x22.dmm"
	name = "Trading ship."
	description = "A trading ship stocked with various goods."

/datum/map_template/shelter/superpose/WoodenCamp
	shelter_id = "WoodenCamp"
	mappath = "maps/submaps/shelters/WoodenCamp-10x10.dmm"
	name = "Wooden camp."
	description = "A very small camping lodge, a quick emergency hut to stave off the planets weather."

/datum/map_template/shelter/superpose/AnimalHospital
	shelter_id = "AnimalHospital"
	mappath = "maps/submaps/shelters/AnimalHospital-20x28.dmm"
	name = "Low-Tech Hospital."
	description = "An animal hospital, does not contain high end medical supplies, better then nothing."

/datum/map_template/shelter/superpose/RestaurationBar
	shelter_id = "RestaurationBar"
	mappath = "maps/submaps/shelters/RestaurationBar-32x32.dmm"
	name = "Resto-Bar"
	description = "A large restaurant for food and drink, two overnight rental rooms and a small garden."

/datum/map_template/shelter/superpose/BroadcastingPod
	shelter_id = "BroadcastingPod"
	mappath = "maps/submaps/shelters/BroadcastingPod-11x9.dmm"
	name = "Broadcasting Pod"
	description = "A small NanoTransen news pod, everything you need to start live news in the most inhospitable places!"

/datum/map_template/shelter/superpose/DemonPoolV2
	shelter_id = "DemonPoolV2"
	mappath = "maps/submaps/shelters/DemonPoolV2-43x28.dmm"
	name = "Demon Pool V2"
	description = "A large redspace corruption with lava, flesh tiles and a small cultist room in the middle. This one is enclosed in rock!"

/datum/map_template/shelter/superpose/PirateShip
	shelter_id = "PirateShip"
	mappath = "maps/submaps/shelters/PirateShip-13x30.dmm"
	name = "Pirate Ship"
	description = "Yarg, a medium size pirate ship filled with loaded canons and empty chest, booty awaits."

/datum/map_template/shelter/superpose/SurvivalHomeV2
	shelter_id = "SurvivalHomeV2"
	mappath = "maps/submaps/shelters/SurvivalHomeV2-9x9.dmm"
	name = "Survival Home V2"
	description = "A medium survival pod that can host a small team, has some basic survival gear."


/datum/map_template/shelter/superpose/SurvivalMechFab
	shelter_id = "SurvivalMechFab"
	mappath = "maps/submaps/shelters/SurvivalMechFab-9x9.dmm"
	name = "Survival Mech Fab"
	description = "A medium survival pod with a mech and some basic mech fabrication machinery, fix and retrofit!"

/datum/map_template/shelter/superpose/SurvivalMethLab
	shelter_id = "SurvivalMethLab"
	mappath = "maps/submaps/shelters/SurvivalMethLab-9x10.dmm"
	name = "Survival Meth Lab"
	description = "A medium survival pod, repurposed and locked for the production of illegal chems. Don't get caught."
/* Removed due to powergaming
/datum/map_template/shelter/superpose/SurvivalScienceV2
	shelter_id = "SurvivalScienceV2"
	mappath = "maps/submaps/shelters/SurvivalScience2-9x9.dmm"
	name = "Survival Science V2"
	description = "NT patented science survival pod, loaded with research terminals, mech fabricator, autolathe and everything to do field research."
*/
/datum/map_template/shelter/superpose/SurvivalSecurityV2
	shelter_id = "SurvivalSecurityV2"
	mappath = "maps/submaps/shelters/SurvivalSecurity2-9x9.dmm"
	name = "Survival Security V2"
	description = "NT patented security survival pod, a high security brig with and some security equipment."

/datum/map_template/shelter/superpose/HillOutpost
	shelter_id = "HillOutpost"
	mappath = "maps/submaps/shelters/HillOutpost-15x11.dmm"
	name = "Hill Outpost"
	description = "A small camping site on top of a hill, with all the basics for survival."

/datum/map_template/shelter/superpose/pizzaparlor
	shelter_id = "PizzaParlor"
	mappath = "maps/submaps/shelters/PizzaParlor-18x19.dmm"
	name = "Pizza Parlor"
	description = "A small locally owned pizza parlor, now with delivery services."

/datum/map_template/shelter/superpose/GrandLibrary
	shelter_id = "GrandLibrary"
	mappath = "maps/submaps/shelters/GrandLibrary-31x24.dmm"
	name = "Pizza Parlor"
	description = "A grand ornate library, more books than you can count."

/datum/map_template/shelter/superpose/logcabin
	shelter_id = "logcabin"
	mappath = "maps/submaps/shelters/Logcabin-19x9.dmm"
	name = "Log Cabin"
	description = "A cozy log cabin with some 'magical' items."

/datum/map_template/shelter/superpose/hotel
	shelter_id = "hotel"
	mappath = "maps/submaps/shelters/Hotel-36x18.dmm"
	name = "Large Sif Hotel"
	description = "A large hotel designed for hospitality of up to 8 people, comes with a kitchen and a bar. May contain pests."

/datum/map_template/shelter/superpose/XenoBotanySetup
	shelter_id = "XenoBotanySetup"
	mappath = "maps/submaps/shelters/XenobotanySetup-19x11.dmm"
	name = "Xenobotany Lab"
	description = "A cozy little lab made for plant life."

/datum/map_template/shelter/superpose/SecondLifeBar
	shelter_id = "SecondLifeBar"
	mappath = "maps/submaps/shelters/secondlifebar-19x25.dmm"
	name = "Second Life Bar"
	description = "A bar for all your hedonistics needs, only the sky is the limit~"

/datum/map_template/shelter/superpose/RipperDocPod
	shelter_id = "RipperDocPod"
	mappath = "maps/submaps/shelters/ripperdocpod-12x15.dmm"
	name = "Ripper Doc"
	description = "A small dubiously legal surgical site for all your cybernetic needs, may contain some illegal items."


// === merged from shelters_vr.dm during hard-fork de-suffix (manually verified) ===
/datum/map_template/shelter
	var/shelter_id
	var/description
	var/blacklisted_turfs
	var/banned_areas
	var/banned_objects
	var/list/door_locations = list() /// Where the door (or doors) are located in XY coordinates, so the capsule deploy preview can show where the doors will be.

/datum/map_template/shelter/New()
	. = ..()
	blacklisted_turfs = typecacheof(list(/turf/unsimulated))
	banned_areas = typecacheof(/area/shuttle)
	banned_objects = list()

/// Checks all turfs within the area of the given deploy location to see if it is a valid shelter area.
/datum/map_template/shelter/proc/check_deploy(turf/deploy_location, is_ship)
	var/affected = get_affected_turfs(deploy_location, centered=TRUE)
	for(var/turf/T in affected)
		var/shelter_status = get_turf_deployability(T, is_ship)
		if(shelter_status != SHELTER_DEPLOY_ALLOWED)
			return shelter_status
	return SHELTER_DEPLOY_ALLOWED

/// Checks a single given turf to see if it is a valid turf to deploy a shelter onto.
/datum/map_template/shelter/proc/get_turf_deployability(turf/T, is_ship)
	var/area/A = get_area(T)
	if(is_type_in_typecache(A, banned_areas) || (A.flags & AREA_BLOCK_INSTANT_BUILDING))
		return SHELTER_DEPLOY_BAD_AREA

	var/banned = is_type_in_typecache(T, blacklisted_turfs)
	if(banned || T.density)
		return SHELTER_DEPLOY_BAD_TURFS
	//Ships can only deploy in space (because their base turf is always turf/space)
	if(is_ship && !is_type_in_typecache(T, typecacheof(/turf/space)))
		return SHELTER_DEPLOY_SHIP_SPACE

	for(var/obj/O in T)
		if((O.density && O.anchored) || is_type_in_typecache(O, banned_objects))
			return SHELTER_DEPLOY_ANCHORED_OBJECTS
	return SHELTER_DEPLOY_ALLOWED

/datum/map_template/shelter/proc/add_roof(turf/deploy_location)
	var/affected = get_affected_turfs(deploy_location, centered=TRUE)
	for(var/turf/T in affected)
		if(isopenspace(T))
			T.ChangeTurf(/turf/simulated/shuttle/floor/voidcraft)

/datum/map_template/shelter/proc/annihilate_plants(turf/deploy_location)
	var/deleted_atoms = 0
	var/affected = get_affected_turfs(deploy_location, centered=TRUE)
	for(var/turf/T in affected)
		for(var/obj/structure/flora/AM in T)
			++deleted_atoms
			qdel(AM)
	admin_notice(span_danger("Annihilated [deleted_atoms] plants."), R_DEBUG)

/datum/map_template/shelter/proc/update_lighting(turf/deploy_location)
	var/affected = get_affected_turfs(deploy_location, centered=TRUE)
	for(var/turf/T in affected)
		T.lighting_build_overlay()

/datum/map_template/shelter/alpha
	name = "Shelter Alpha"
	shelter_id = "shelter_alpha"
	description = "(5x5) A cosy self-contained pressurized shelter, with \
		built-in navigation, entertainment, medical facilities and a \
		sleeping area! Order now, and we'll throw in a TINY FAN, \
		absolutely free!"
	mappath = "maps/submaps/shelters/5x5/shelter_1.dmm"
	door_locations = list(list(3,1))

/datum/map_template/shelter/beta
	name = "Shelter Beta"
	shelter_id = "shelter_beta"
	description = "(7x7) An extremely luxurious shelter, containing all \
		the amenities of home, including carpeted floors, hot and cold \
		running water, a gourmet three course meal, cooking facilities, \
		and a deluxe companion to keep you from getting lonely during \
		an ash storm."
	mappath = "maps/submaps/shelters/7x7/shelter_2.dmm"
	door_locations = list(list(4,1))

/datum/map_template/shelter/gamma
	name = "Shelter Gamma"
	shelter_id = "shelter_gamma"
	description = "(11x11) A luxury elite bar which holds an entire bar \
		along with two vending machines, tables, and a restroom that \
		also has a sink. This isn't a survival capsule and so you can \
		expect that this won't save you if you're bleeding out to \
		death."
	mappath = "maps/submaps/shelters/11x11/shelter_3.dmm"
	door_locations = list(
		list(6,1),
		list(1,6),
		list(1,9))

/datum/map_template/shelter/delta
	name = "Shelter Delta"
	shelter_id = "shelter_delta"
	description = "(11x11) A small firebase that contains equipment and supplies \
		for roughly a squad of military troops. Large quantities of \
		supplies allow it to hold out for an extended period of time\
		and a built in medical facility allows field treatment to be \
		possible."
	mappath = "maps/submaps/shelters/11x11/shelter_4.dmm"
	door_locations = list(
		list(1,6),
		list(6,1),
		list(11,6))

/datum/map_template/shelter/epsilon
	name = "Shelter Epsilon"
	shelter_id = "shelter_epsilon"
	description = "(10x5) An escape pod, with a mediocre amount of supplies \
		for escaping a dying ship as soon as possible."
	mappath = "maps/offmap/om_ships/shelter_5.dmm"
	door_locations = list(list(10,3))

/datum/map_template/shelter/cabin
	name = "Shelter Cabin"
	shelter_id = "shelter_cab"
	description = "(7x7) A small cabin; turned into a shelter capsule. Includes dorm amenities, and a nice dinner."
	mappath = "maps/submaps/shelters/7x7/shelter_cab.dmm"
	door_locations = list(list(4,1))

/datum/map_template/shelter/cabin_deluxe
	name = "Shelter Deluxe Cabin"
	shelter_id = "shelter_cab_deluxe"
	description = "(11x11) A glamorously furnished cabin packed away in your pocket. \
		Includes a private dormitory, bathroom, dining room, and a very \
		compactly designed kitchen. Designed for a comfortable extended \
		stay in isolated wilderness survival scenarios."
	mappath = "maps/submaps/shelters/11x11/shelter_luxury_cabin.dmm"
	door_locations = list(
		list(1,3),
		list(6,11),
		list(6,1)
		)

/datum/map_template/shelter/phi
	name = "Shelter Phi"
	shelter_id = "shelter_phi"
	description = "An heavily modified variant of the luxury shelter, \
		this particular model has extra food, drinks, and other supplies. \
		Originally designed for use by colonists on worlds with little to \
		to no contact, the expense of these shelters have prevented them \
		from seeing common use."
	mappath = "maps/submaps/shelters/7x7/shelter_a.dmm"
	door_locations = list(list(4,1))

/datum/map_template/shelter/chi
	name = "Shelter Chi"
	shelter_id = "shelter_chi"
	description = "A custom, from-the-ground-up variant of the shelter \
	capsule. Many of the survival utilities have been stripped away in favor \
	of recreational facilities and a more comfortable living quarters. The \
	definition of \"form over function,\" in capsule form!"
	mappath = "maps/submaps/shelters/7x8/shelter_h.dmm"
	door_locations = list(list(4,1),list(7,4))

/datum/map_template/shelter/rec
	name = "Shelter Rec Room"
	shelter_id = "shelter_recroom"
	description = "(9x9) A recreational room in a pocket, offering a gaming table with poker chips, dice, and cards to host group gaming activities, as well as a small arcade for more individual experiences. While offering absolutely nothing that will help someone survive physically aside from a safely isolated atmosphere, the intellectual stimulation provided from the gaming facilities within have been chosen to assist and keep one's mind sharp."
	mappath = "maps/submaps/shelters/9x9/shelter_recroom.dmm"
	door_locations = list(
		list(1,5),
		list(4,9),
		list(5,1),
		list(9,4),
		)

/datum/map_template/shelter/sauna
	name = "Shelter Sauna"
	shelter_id = "shelter_sauna"
	description = "(7x7) A luxurious sauna in your pocket. Complete with privacy features, a changing and locker room, and of course a decently spacious sauna room with three benches to rest on."
	mappath = "maps/submaps/shelters/7x7/shelter_sauna.dmm"
	door_locations = list(list(4,1))

/datum/map_template/shelter/cafe
	name = "Shelter Cafe"
	shelter_id = "shelter_cafe"
	description = "(11x11) A fully stocked and equipped cafe in your pocket. While this won't save you if you're dying, it will ensure that you and anyone who happens to be with you will never suffer from caffeine withdrawal!"
	mappath = "maps/submaps/shelters/11x11/shelter_cafe.dmm"
	door_locations = list(
		list(1,6),
		list(6,1),
		list(11,6),
		list(11,9)
		)

/datum/map_template/shelter/luxuryrecroom
	name = "Shelter Luxury Rec Room"
	shelter_id = "shelter_luxury_recroom"
	description = "(11x11) The surfluid within this capsule is a carefully programmed monument to hedonism. Unlike its smaller cousin, this rec room variant  sports a larger gambling table supporting up to seven players, more vending machines for players' needs, and even a small private dorm room. If you have any desire for a fully private, self-contained gambling room completely isolated from the world outside, this is your perfect answer."
	mappath = "maps/submaps/shelters/11x11/shelter_luxury_recroom.dmm"
	door_locations = list(
		list(6,1),
		list(6,11),
		list(11,6)
		)

/datum/map_template/shelter/kitchen
	name = "Shelter Kitchen"
	shelter_id = "shelter_kitchen"
	description = "(7x7) A fully stocked, functional kitchen in your pocket, equipped with an oven, fryer, grill, oven, microwave, and blender. It even comes with a pre-stocked storage of basic ingredients, to make starting your culinary pursuits easier to begin as soon as you pop open the capsule!"
	mappath = "maps/submaps/shelters/7x7/shelter_kitchen.dmm"
	door_locations = list(
		list(4,1),
		list(1,4),
		list(7,4)
		)

/datum/map_template/shelter/iota
	name = "Shelter Iota"
	shelter_id = "shelter_pocket_dorm"
	description = "(5x5) An alternate configuration of Shelter Alpha. This one is more spatially efficient and supports two people inside it, but compromises some shelter equipment to make room for it."
	mappath = "maps/submaps/shelters/5x5/shelter_pocket_dorm.dmm"
	door_locations = list(list(3,1))

/datum/map_template/shelter/zeta
	name = "Shelter Zeta"
	shelter_id = "shelter_luxury_alt"
	description = "(7x7) An alternate configuration of Shelter Beta, prominently featuring both a windowed view of the exterior as well as the means to tint the windows for superior privacy."
	mappath = "maps/submaps/shelters/7x7/shelter_luxury_alt.dmm"
	door_locations = list(list(4,1))

/datum/map_template/shelter/loss_1
	name = "Shelter L1"
	shelter_id = "shelter_loss1"
	description = "(5x5) North-west quadrant."
	mappath = "maps/submaps/shelters/5x5/shelter_loss_1.dmm"
	door_locations = list(
		list(1,3),
		list(3,5),
		list(3,1),
		list(5,3))

/datum/map_template/shelter/loss_2
	name = "Shelter L2"
	shelter_id = "shelter_loss2"
	description = "(5x5) North-east quadrant."
	mappath = "maps/submaps/shelters/5x5/shelter_loss_2.dmm"
	door_locations = list(
		list(1,3),
		list(3,1))

/datum/map_template/shelter/loss_3
	name = "Shelter L3"
	shelter_id = "shelter_loss3"
	description = "(5x5) South-west quadrant."
	mappath = "maps/submaps/shelters/5x5/shelter_loss_3.dmm"
	door_locations = list(
		list(3,5),
		list(5,3))

/datum/map_template/shelter/loss_4
	name = "Shelter L4"
	shelter_id = "shelter_loss4"
	description = "(5x5) South-east quadrant."
	mappath = "maps/submaps/shelters/5x5/shelter_loss_4.dmm"
	door_locations = list(
		list(1,3),
		list(3,5))

// EXTREMELY DANGEROUS ADMIN-ONLY SHELTERS I BEG YOU DO NOT SPAWN THESE EXCEPT FOR A DISASTROUS BIT

/datum/map_template/shelter/tesla
	name = "Shelter Tesla"
	description = "(11x11) A whole tesla engine setup, complete with a fully charged SMES cell ready to power the emitters. Using this is probably an exceptionally terrible idea."
	shelter_id = "shelter_tesla"
	mappath = "maps/submaps/shelters/11x11/shelter_tesla.dmm"
	door_locations = list(
		list(1,6),
		list(6,1),
		list(6,11))

//Redspace capsule shelters - here be weird shit.

/datum/map_template/shelter/nerd_dungeon_evil
	name = "Shelter Nerd Dungeon Evil"
	shelter_id = "shelter_nerd_dungeon_evil"
	mappath = "maps/submaps/shelters/randomshelters/7x7/shelter_nerd_dungeon_evil.dmm"
	door_locations = list(list(1,4))

/datum/map_template/shelter/nerd_dungeon_good
	name = "Shelter Nerd Dungeon Good"
	shelter_id = "shelter_nerd_dungeon_good"
	mappath = "maps/submaps/shelters/randomshelters/7x7/shelter_nerd_dungeon_good.dmm"
	door_locations = list(list(1,4))

/datum/map_template/shelter/dangerous_pool
	name = "Shelter Dangerous Pool"
	shelter_id = "shelter_dangerous_pool"
	mappath = "maps/submaps/shelters/randomshelters/7x7/shelter_dangerous_pool.dmm"
	door_locations = list(list(1,4))

/datum/map_template/shelter/pizza_kitchen
	name = "Shelter Pizza Kitchen"
	shelter_id = "shelter_pizza_kitchen"
	mappath = "maps/submaps/shelters/randomshelters/7x7/shelter_pizza.dmm"
	door_locations = list(list(1,4))

/datum/map_template/shelter/tiny_space
	name = "Shelter Smole Space"
	shelter_id = "shelter_tiny_space"
	mappath = "maps/submaps/shelters/randomshelters/7x7/shelter_tiny_space.dmm"
	door_locations = list(list(1,4))

/datum/map_template/shelter/christmas
	name = "Shelter Christmas"
	shelter_id = "shelter_christmas"
	mappath = "maps/submaps/shelters/randomshelters/7x7/shelter_christmas.dmm"
	door_locations = list(list(1,4))

/datum/map_template/shelter/methlab
	name = "Shelter Meth Lab"
	shelter_id = "shelter_methlab"
	mappath = "maps/submaps/shelters/randomshelters/7x7/shelter_methlab.dmm"
	door_locations = list(list(1,4))

/datum/map_template/shelter/blacksmith
	name = "Shelter Blacksmith"
	shelter_id = "shelter_blacksmith"
	mappath = "maps/submaps/shelters/randomshelters/7x7/shelter_blacksmith.dmm"
	door_locations = list(list(1,4))

/datum/map_template/shelter/gallery
	name = "Shelter Art Gallery"
	shelter_id = "shelter_gallery"
	mappath = "maps/submaps/shelters/randomshelters/7x7/shelter_gallery.dmm"
	door_locations = list(list(1,4))

/datum/map_template/shelter/garden
	name = "Shelter Garden"
	shelter_id = "shelter_garden"
	mappath = "maps/submaps/shelters/randomshelters/7x7/shelter_garden.dmm"
	door_locations = list(list(1,4))

/datum/map_template/shelter/mimic_hell
	name = "Shelter Mimic Hell"
	shelter_id = "shelter_mimic_hell"
	mappath = "maps/submaps/shelters/randomshelters/7x7/shelter_mimic_hell.dmm"
	door_locations = list(list(1,4))

/datum/map_template/shelter/off_color_bedrooms
	name = "Shelter Off-Color Bedrooms"
	shelter_id = "shelter_off_color"
	mappath = "maps/submaps/shelters/randomshelters/7x7/shelter_off_color.dmm"
	door_locations = list(list(1,4))

/datum/map_template/shelter/living_room
	name = "Shelter Living Room"
	shelter_id = "shelter_living_room"
	mappath = "maps/submaps/shelters/randomshelters/7x7/shelter_living_room.dmm"
	door_locations = list(list(1,4))

/datum/map_template/shelter/candlelit_dinner
	name = "Shelter Candlelit Dinner"
	shelter_id = "shelter_candlelit_dinner"
	mappath = "maps/submaps/shelters/randomshelters/7x7/shelter_candlelit_dinner.dmm"
	door_locations = list(list(1,4))
