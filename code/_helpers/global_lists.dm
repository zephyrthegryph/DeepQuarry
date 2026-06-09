//Since it didn't really belong in any other category, I'm putting this here
//This is for procs to replace all the goddamn 'in world's that are chilling around the code

GLOBAL_LIST_EMPTY(player_list)						//List of all mobs **with clients attached**. Excludes /mob/new_player
GLOBAL_LIST_EMPTY(mob_list)							//List of all mobs, including clientless
GLOBAL_LIST_EMPTY(human_mob_list)					//List of all human mobs and sub-types, including clientless
GLOBAL_LIST_EMPTY(silicon_mob_list)					//List of all silicon mobs, including clientless
GLOBAL_LIST_EMPTY(ai_list)							//List of all AIs, including clientless
GLOBAL_LIST_EMPTY(living_mob_list)					//List of all alive mobs, including clientless. Excludes /mob/new_player
GLOBAL_LIST_EMPTY(dead_mob_list)					//List of all dead mobs, including clientless. Excludes /mob/new_player
GLOBAL_LIST_EMPTY(observer_mob_list)				//List of all /mob/observer/dead, including clientless.
GLOBAL_LIST_EMPTY(listening_objects)				//List of all objects which care about receiving messages (communicators, radios, etc)
GLOBAL_LIST_EMPTY(cleanbot_reserved_turfs)			//List of all turfs currently targeted by some cleanbot

GLOBAL_LIST_EMPTY(cable_list)						//Index for all cables, so that powernets don't have to look through the entire world all the time
GLOBAL_LIST_EMPTY(landmarks_list)					//list of all landmarks created
GLOBAL_LIST_EMPTY(event_triggers)					//Associative list of creator_ckey:list(landmark references) for event triggers
GLOBAL_LIST_EMPTY(surgery_steps)					//list of all surgery steps  |BS12

GLOBAL_LIST_EMPTY(mechas_list)						//list of all mechs. Used by hostile mobs target tracking.
GLOBAL_LIST_EMPTY_TYPED(PDAs, /obj/item/pda)
GLOBAL_LIST_EMPTY_TYPED(all_communicators, /obj/item/communicator)

// Those networks can only be accessed by pre-existing terminals. AIs and new terminals can't use them.
GLOBAL_LIST_INIT(restricted_camera_networks, list(NETWORK_ERT,NETWORK_MERCENARY,"Secret", NETWORK_COMMUNICATORS))

#define all_genders_define_list list(MALE,FEMALE,PLURAL,NEUTER,HERM)
#define all_genders_text_list list("Male","Female","Plural","Neuter","Herm")
#define pronoun_set_to_genders list(\
			"He/Him" = MALE,\
			"She/Her" = FEMALE,\
			"It/Its" = NEUTER,\
			"They/Them" = PLURAL,\
			"Shi/Hir" = HERM\
			)
#define genders_to_pronoun_set list(\
			MALE = "He/Him",\
			FEMALE = "She/Her",\
			NEUTER = "It/Its",\
			PLURAL = "They/Them",\
			HERM = "Shi/Hir"\
			)

// Times that players are allowed to respawn ("ckey" = world.time)
GLOBAL_LIST_EMPTY(respawn_timers)

// Holomaps
GLOBAL_LIST_EMPTY(holomap_markers)
GLOBAL_LIST_EMPTY(mapping_units)
GLOBAL_LIST_EMPTY(mapping_beacons)

//Preferences stuff
	//Hairstyles
GLOBAL_LIST_EMPTY(hair_styles_list)			//stores /datum/sprite_accessory/hair indexed by name
GLOBAL_LIST_EMPTY(hair_styles_male_list)
GLOBAL_LIST_EMPTY(hair_styles_female_list)
GLOBAL_LIST_EMPTY(facial_hair_styles_list)	//stores /datum/sprite_accessory/facial_hair indexed by name
GLOBAL_LIST_EMPTY(facial_hair_styles_male_list)
GLOBAL_LIST_EMPTY(facial_hair_styles_female_list)
GLOBAL_LIST_EMPTY(body_marking_styles_list)		//stores /datum/sprite_accessory/marking indexed by name
GLOBAL_LIST_EMPTY(body_marking_nopersist_list)	// Body marking styles, minus non-genetic markings and augments
GLOBAL_LIST_EMPTY(ear_styles_list)	// Stores /datum/sprite_accessory/ears indexed by type
GLOBAL_LIST_EMPTY(tail_styles_list)	// Stores /datum/sprite_accessory/tail indexed by type
GLOBAL_LIST_EMPTY(wing_styles_list)	// Stores /datum/sprite_accessory/wing indexed by type

GLOBAL_LIST_EMPTY(custom_species_bases) // Species that can be used for a Custom Species icon base

	//Customizables
GLOBAL_LIST_INIT(headsetlist, list("Standard","Bowman","Earbud"))
GLOBAL_LIST_INIT(backbaglist, list("Nothing", "Backpack", "Satchel", "Satchel Alt", "Messenger Bag", "Sports Bag", "Strapless Satchel"))
GLOBAL_LIST_INIT(pdachoicelist, list("Default", "Slim", "Old", "Rugged", "Holographic", "Wrist-Bound","Slider", "Vintage"))
GLOBAL_LIST_INIT(exclude_jobs, list(/datum/job/ai,/datum/job/cyborg))

GLOBAL_LIST_EMPTY_TYPED(message_servers, /obj/machinery/message_server)
GLOBAL_LIST_INIT_TYPED(supply_drop, /datum/supply_drop_loot, dd_sortedObjectList(init_subtypes(/datum/supply_drop_loot)))
// Runes
GLOBAL_LIST_EMPTY(rune_list)
GLOBAL_LIST_EMPTY(escape_list)
GLOBAL_LIST_EMPTY(endgame_exits)
GLOBAL_LIST_EMPTY(endgame_safespawns)

GLOBAL_LIST_INIT(syndicate_access, list(ACCESS_MAINT_TUNNELS, ACCESS_SYNDICATE, ACCESS_EXTERNAL_AIRLOCKS))

// Ores (for mining)
GLOBAL_LIST_EMPTY(ore_data)
GLOBAL_LIST_EMPTY(alloy_data)

// Strings which corraspond to bodypart covering flags, useful for outputting what something covers.
GLOBAL_LIST_INIT(string_part_flags, list(
	"head" = HEAD,
	"face" = FACE,
	"eyes" = EYES,
	"upper body" = UPPER_TORSO,
	"lower body" = LOWER_TORSO,
	"legs" = LEGS,
	"feet" = FEET,
	"arms" = ARMS,
	"hands" = HANDS
))

// Strings which corraspond to slot flags, useful for outputting what slot something is.
GLOBAL_LIST_INIT(string_slot_flags, list(
	"back" = SLOT_BACK,
	"face" = SLOT_MASK,
	"waist" = SLOT_BELT,
	"ID slot" = SLOT_ID,
	"ears" = SLOT_EARS,
	"eyes" = SLOT_EYES,
	"hands" = SLOT_GLOVES,
	"head" = SLOT_HEAD,
	"feet" = SLOT_FEET,
	"exo slot" = SLOT_OCLOTHING,
	"body" = SLOT_ICLOTHING,
	"uniform" = SLOT_TIE,
	"holster" = SLOT_HOLSTER
))

GLOBAL_LIST_EMPTY(mannequins)
/proc/get_mannequin(ckey = "NULL")
	var/mob/living/carbon/human/dummy/mannequin/M = GLOB.mannequins[ckey]
	if(!istype(M))
		GLOB.mannequins[ckey] = new /mob/living/carbon/human/dummy/mannequin(null)
		M = GLOB.mannequins[ckey]
	return M

/proc/del_mannequin(ckey = "NULL")
	GLOB.mannequins-= ckey

//////////////////////////
/////Initial Building/////
//////////////////////////

/proc/make_datum_reference_lists()
	var/list/paths

	//Hair - Initialise all /datum/sprite_accessory/hair into an list indexed by hair-style name
	paths = subtypesof(/datum/sprite_accessory/hair)
	for(var/path in paths)
		var/datum/sprite_accessory/hair/H = new path()
		GLOB.hair_styles_list[H.name] = H
		switch(H.gender)
			if(MALE)	GLOB.hair_styles_male_list += H.name
			if(FEMALE)	GLOB.hair_styles_female_list += H.name
			else
				GLOB.hair_styles_male_list += H.name
				GLOB.hair_styles_female_list += H.name

	//Facial Hair - Initialise all /datum/sprite_accessory/facial_hair into an list indexed by facialhair-style name
	paths = subtypesof(/datum/sprite_accessory/facial_hair)
	for(var/path in paths)
		var/datum/sprite_accessory/facial_hair/H = new path()
		GLOB.facial_hair_styles_list[H.name] = H
		switch(H.gender)
			if(MALE)	GLOB.facial_hair_styles_male_list += H.name
			if(FEMALE)	GLOB.facial_hair_styles_female_list += H.name
			else
				GLOB.facial_hair_styles_male_list += H.name
				GLOB.facial_hair_styles_female_list += H.name

	//Body markings - Initialise all /datum/sprite_accessory/marking into an list indexed by marking name
	paths = subtypesof(/datum/sprite_accessory/marking)
	for(var/path in paths)
		var/datum/sprite_accessory/marking/M = new path()
		GLOB.body_marking_styles_list[M.name] = M
		if(!M.genetic)
			GLOB.body_marking_nopersist_list[M.name] = M

	//Surgery Steps - Initialize all /datum/surgery_step into a list
	paths = subtypesof(/datum/surgery_step)
	for(var/T in paths)
		var/datum/surgery_step/S = new T
		GLOB.surgery_steps += S
	sort_surgeries()

	//Languages
	paths = subtypesof(/datum/language)
	for(var/T in paths)
		var/datum/language/L = new T
		if (isnull(GLOB.all_languages[L.name]))
			GLOB.all_languages[L.name] = L
		else
			if(isnull(GLOB.language_name_conflicts[L.name]))
				GLOB.language_name_conflicts[L.name] = list(GLOB.all_languages[L.name])
			GLOB.language_name_conflicts[L.name] += L

	for (var/language_name in GLOB.all_languages)
		var/datum/language/L = GLOB.all_languages[language_name]
		if(!(L.flags & NONGLOBAL))
			if(isnull(GLOB.language_keys[L.key]))
				GLOB.language_keys[L.key] = L
			else
				if(isnull(GLOB.language_key_conflicts[L.key]))
					GLOB.language_key_conflicts[L.key] = list(GLOB.language_keys[L.key])
				GLOB.language_key_conflicts[L.key] += L

	//Species
	var/rkey = 0
	paths = subtypesof(/datum/species)
	for(var/T in paths)

		rkey++

		var/datum/species/S = T
		if(!initial(S.name))
			continue

		S = new T
		S.race_key = rkey //Used in mob icon caching.
		GLOB.all_species[S.name] = S

	//Shakey shakey shake
	sortTim(GLOB.all_species, GLOBAL_PROC_REF(cmp_species), associative = TRUE)

	//Split up the rest
	for(var/speciesname in GLOB.all_species)
		var/datum/species/S = GLOB.all_species[speciesname]
		if(!(S.spawn_flags & SPECIES_IS_RESTRICTED))
			GLOB.playable_species += S.name
		if(S.spawn_flags & SPECIES_IS_WHITELISTED)
			GLOB.whitelisted_species += S.name

	// Suit cyclers
	paths = subtypesof(/datum/suit_cycler_choice/department)
	for(var/datum/suit_cycler_choice/SCC as anything in paths)
		if(!initial(SCC.name))
			continue
		GLOB.suit_cycler_departments += new SCC()
	paths = subtypesof(/datum/suit_cycler_choice/species)
	for(var/datum/suit_cycler_choice/SCC as anything in paths)
		if(!initial(SCC.name))
			continue
		GLOB.suit_cycler_species += new SCC()
	paths = subtypesof(/datum/suit_cycler_choice/department/emag)
	for(var/datum/suit_cycler_choice/SCC as anything in paths)
		if(!initial(SCC.name))
			continue
		GLOB.suit_cycler_emagged += new SCC()

	//Ores
	paths = subtypesof(/datum/ore)
	for(var/oretype in paths)
		var/datum/ore/OD = new oretype()
		GLOB.ore_data[OD.name] = OD

	paths = subtypesof(/datum/alloy)
	for(var/alloytype in paths)
		GLOB.alloy_data += new alloytype()

	//Closet appearances
	GLOB.closet_appearances = GLOB.decls_repository.get_decls_of_type(/datum/decl/closet_appearance)

	paths = subtypesof(/datum/sprite_accessory/ears)
	for(var/path in paths)
		var/obj/item/clothing/head/instance = new path()
		GLOB.ear_styles_list[path] = instance

	// Custom Tails
	paths = subtypesof(/datum/sprite_accessory/tail) - /datum/sprite_accessory/tail/taur
	for(var/path in paths)
		var/datum/sprite_accessory/tail/instance = new path()
		GLOB.tail_styles_list[path] = instance

	// Custom Wings
	paths = subtypesof(/datum/sprite_accessory/wing)
	for(var/path in paths)
		var/datum/sprite_accessory/wing/instance = new path()
		GLOB.wing_styles_list[path] = instance

	paths = typesof(/datum/digest_mode)
	for(var/path in paths)
		var/datum/digest_mode/DM = new path
		GLOB.digest_modes[DM.id] = DM
	init_crafting_recipes(GLOB.crafting_recipes)

	paths = subtypesof(/datum/ai_laws)
	for(var/path in paths)
		var/datum/ai_laws/laws = new path
		GLOB.admin_laws += laws
		if(laws.selectable)
			GLOB.player_laws += laws
/*
	// Custom species traits
	paths = subtypesof(/datum/trait)
	for(var/path in paths)
		var/datum/trait/instance = new path()
		if(!instance.name)
			continue //A prototype or something
		var/cost = instance.cost
		traits_costs[path] = cost
		all_traits[path] = instance
		switch(cost)
			if(-INFINITY to -0.1)
				negative_traits[path] = instance
			if(0)
				neutral_traits[path] = instance
			if(0.1 to INFINITY)
				positive_traits[path] = instance
*/

	// Custom species icon bases
	///These are icons that you DO NOT want to be selectable!
	var/list/blacklisted_icons = list(SPECIES_CUSTOM,SPECIES_PROMETHEAN)
	///These are icons that you WANT to be selectable, even if they're a whitelist species!
	var/list/whitelisted_icons = list(SPECIES_FENNEC,SPECIES_XENOHYBRID,SPECIES_VOX,SPECIES_ZORREN_DARK,SPECIES_SHADEKIN) //CHOMEdit
	for(var/species_name in GLOB.playable_species)
		if(species_name in blacklisted_icons)
			continue
		var/datum/species/S = GLOB.all_species[species_name]
		if(S.spawn_flags & SPECIES_IS_WHITELISTED)
			continue
		GLOB.custom_species_bases += species_name
	for(var/species_name in whitelisted_icons)
		GLOB.custom_species_bases += species_name

	// Create frame types.
	populate_frame_types()

	// Create robolimbs for chargen.
	populate_robolimb_list()

	cache_no_ceiling_image()

/// Inits the crafting recipe list, sorting crafting recipe requirements in the process.
/proc/init_crafting_recipes(list/crafting_recipes)
	for(var/path in subtypesof(/datum/crafting_recipe))
		var/datum/crafting_recipe/recipe = new path()
		recipe.reqs = sortList(recipe.reqs, GLOBAL_PROC_REF(cmp_crafting_req_priority))
		crafting_recipes += recipe
	return crafting_recipes
/* // Uncomment to debug chemical reaction list.
/client/verb/debug_chemical_list()

	for (var/reaction in chemical_reactions_list)
		. += "chemical_reactions_list\[\"[reaction]\"\] = \"[chemical_reactions_list[reaction]]\"\n"
		if(islist(chemical_reactions_list[reaction]))
			var/list/L = chemical_reactions_list[reaction]
			for(var/t in L)
				. += "    has: [t]\n"
	to_world(.)
*/
//Hexidecimal numbers
GLOBAL_LIST_INIT(hexNums, list("0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F"))

GLOBAL_LIST_INIT(selectable_footstep, list(
	"Default" = FOOTSTEP_MOB_HUMAN,
	"Claw" = FOOTSTEP_MOB_CLAW,
	"Light Claw" = FOOTSTEP_MOB_TESHARI,
	"Slither" = FOOTSTEP_MOB_SLITHER,
	"Mech" = FOOTSTEP_MOB_MECHY,
	"Heavy" = FOOTSTEP_MOB_HEAVY_ALT
))

// Put any artifact effects that are duplicates, unique, or otherwise unwated in here! This prevents them from spawning via RNG.
GLOBAL_LIST_INIT(blacklisted_artifact_effects, list(
	/datum/artifact_effect/gas/sleeping,
	/datum/artifact_effect/gas/oxy,
	/datum/artifact_effect/gas/carbondiox,
	/datum/artifact_effect/gas/fuel,
	/datum/artifact_effect/gas/nitro,
	/datum/artifact_effect/gas/phoron,
	/datum/artifact_effect/extreme
))

//stuff that only synths can eat
GLOBAL_LIST_INIT(edible_tech, list(/obj/item/cell,
				/obj/item/circuitboard,
				/obj/item/integrated_circuit,
				/obj/item/broken_device,
				/obj/item/brokenbug,
				))

GLOBAL_LIST_INIT(item_digestion_blacklist, list(
		/obj/item/hand_tele,
		/obj/item/card/id,
		/obj/item/gun,
		/obj/item/pinpointer,
		/obj/item/clothing/shoes/magboots,
		/obj/item/areaeditor/blueprints,
		/obj/item/disk/nuclear,
		/obj/item/perfect_tele_beacon,
		/obj/item/organ/internal/brain/slime,
		/obj/item/mmi/digital/posibrain,
		/obj/item/mmi/digital/robot,
		/obj/item/rig/protean))

///A list of stuff we do NOT want being deconstructed. Either due to how critical it is (ID/nuke disk) or buggy (holders and paicards)
GLOBAL_LIST_INIT(item_deconstruction_blacklist, list(
		/obj/item/card/id,
		/obj/item/areaeditor/blueprints,
		/obj/item/disk/nuclear,
		/obj/item/perfect_tele_beacon,
		/obj/item/organ/internal/brain,
		/obj/item/mmi,
		/obj/item/rig/protean,
		/obj/item/holder,
		/obj/item/paicard,
		/obj/item/stack/material/cyborg,
		/obj/item/storage))

///A list of chemicals that are banned from being obtainable through means that generate chemicals. These chemicals are either lame, annoying, pref-breaking, or OP (This list does NOT include reactions)
GLOBAL_LIST_INIT(obtainable_chemical_blacklist, list(
	REAGENT_ID_ADMINORDRAZINE,
	REAGENT_ID_NUTRIMENT,
	REAGENT_ID_MACROCILLIN,
	REAGENT_ID_MICROCILLIN,
	REAGENT_ID_NORMALCILLIN,
	REAGENT_ID_MAGICDUST,
	REAGENT_ID_SUPERMATTER
	))

GLOBAL_LIST_INIT(reagent_containers_can_be_placed_into, list(
	REAGENT_CONTAINER_CAN_BE_PLACED_INTO_DEFAULT = list(
		/obj/machinery/chem_master,
		/obj/machinery/chemical_dispenser,
		/obj/machinery/reagentgrinder,
		/obj/structure/table,
		/obj/structure/closet,
		/obj/structure/sink,
		/obj/item/storage,
		/obj/machinery/atmospherics/unary/cryo_cell,
		/obj/machinery/dna_scannernew,
		/obj/item/grenade/chem_grenade,
		/mob/living/bot/medbot,
		/obj/item/storage/secure/safe,
		/obj/machinery/iv_drip,
		/obj/structure/medical_stand,
		/obj/machinery/disposal,
		/mob/living/simple_mob/animal/passive/cow,
		/mob/living/simple_mob/animal/goat,
		/obj/machinery/sleeper,
		/obj/machinery/smartfridge,
		/obj/machinery/biogenerator,
		/obj/structure/frame,
		/obj/machinery/radiocarbon_spectrometer,
		/obj/machinery/portable_atmospherics/powered/reagent_distillery,
		/obj/machinery/computer/pandemic,
		/obj/machinery/reagent_refinery,
		/obj/vehicle/train/trolley_tank,
		/obj/machinery/feeder, // 
		/obj/machinery/chemical_synthesizer, // 
		/obj/machinery/food_replicator
	),
	REAGENT_CONTAINER_CAN_BE_PLACED_INTO_WATERCOOLER = list(
		/obj/structure/table,
		/obj/structure/closet,
		/obj/structure/sink
	),
	REAGENT_CONTAINER_CAN_BE_PLACED_INTO_NONE = list(
	),
))

GLOBAL_LIST_EMPTY(item_tf_spawnpoints) // Global variable tracking which items are item tf spawnpoints

// Options for transforming into a different mob in virtual reality.
GLOBAL_LIST_INIT(vr_mob_tf_options, list(
	"Borg" = /mob/living/silicon/robot,
	"Cortical borer" = /mob/living/simple_mob/animal/borer/non_antag,
	"Hyena" = /mob/living/simple_mob/animal/hyena,
	"Giant spider" = /mob/living/simple_mob/animal/giant_spider/thermic,
	"Armadillo" = /mob/living/simple_mob/animal/passive/armadillo,
	"Parrot" = /mob/living/simple_mob/animal/passive/bird/parrot,
	"Cat" = /mob/living/simple_mob/animal/passive/cat,
	"Corgi" = /mob/living/simple_mob/animal/passive/dog/corgi,
	"Squirrel" = /mob/living/simple_mob/vore/squirrel,
	"Frog" = /mob/living/simple_mob/vore/aggressive/frog,
	"Seagull" =/mob/living/simple_mob/vore/seagull,
	"Fox" = /mob/living/simple_mob/animal/passive/fox,
	"Racoon" = /mob/living/simple_mob/animal/passive/raccoon,
	"Shantak" = /mob/living/simple_mob/animal/sif/shantak,
	"Goose" = /mob/living/simple_mob/animal/space/goose,
	"Space shark" = /mob/living/simple_mob/animal/space/shark,
	"Synx" = /mob/living/simple_mob/animal/synx,
	"Dire wolf" = /mob/living/simple_mob/vore/wolf/direwolf,
	"Construct Artificer" = /mob/living/simple_mob/construct/artificer,
	"Tech golem" = /mob/living/simple_mob/mechanical/technomancer_golem,
	"Metroid" = /mob/living/simple_mob/metroid/juvenile/baby,
	"Otie" = /mob/living/simple_mob/vore/otie/cotie/chubby,
	"Red-eyed Shadekin" = /mob/living/simple_mob/shadekin/red,
	"Blue-eyed Shadekin" = /mob/living/simple_mob/shadekin/blue,
	"Purple-eyed Shadekin" = /mob/living/simple_mob/shadekin/purple,
	"Green-eyed Shadekin" = /mob/living/simple_mob/shadekin/green,
	"Yellow-eyed Shadekin" = /mob/living/simple_mob/shadekin/yellow,
	"Slime" = /mob/living/simple_mob/slime/xenobio/metal,
	"Corrupt hound" = /mob/living/simple_mob/vore/aggressive/corrupthound,
	"Deathclaw" = /mob/living/simple_mob/vore/aggressive/deathclaw/den,
	"Weretiger" = /mob/living/simple_mob/vore/weretiger,
	"Mimic" = /mob/living/simple_mob/vore/aggressive/mimic/floor/plating,
	"Giant rat" = /mob/living/simple_mob/vore/aggressive/rat,
	"Catslug" = /mob/living/simple_mob/vore/alienanimals/catslug,
	"Dust jumper" = /mob/living/simple_mob/vore/alienanimals/dustjumper,
	"Space ghost" = /mob/living/simple_mob/vore/alienanimals/spooky_ghost,
	"Teppi" = /mob/living/simple_mob/vore/alienanimals/teppi,
	"Bee" = /mob/living/simple_mob/vore/bee,
	"Dragon" = /mob/living/simple_mob/vore/bigdragon/friendly,
	"Riftwalker" = /mob/living/simple_mob/vore/demon/wendigo,
	"Horse" = /mob/living/simple_mob/vore/horse/big,
	"Morph" = /mob/living/simple_mob/vore/morph,
	"Leopardmander" = /mob/living/simple_mob/vore/leopardmander,
	"Rabbit" = /mob/living/simple_mob/vore/rabbit,
	"Red panda" = /mob/living/simple_mob/vore/redpanda,
	"Sect drone" = /mob/living/simple_mob/vore/sect_drone,
	"Armalis vox" = /mob/living/simple_mob/vox/armalis,
	"Xeno hunter" = /mob/living/simple_mob/xeno_ch/hunter,
	"Xeno queen" = /mob/living/simple_mob/xeno_ch/queen/maid,
	"Xeno sentinel" = /mob/living/simple_mob/xeno_ch/sentinel,
	"Space carp" = /mob/living/simple_mob/animal/space/carp,
	"Jelly blob" = /mob/living/simple_mob/vore/jelly,
	"SWOOPIE XL" = /mob/living/simple_mob/vore/aggressive/corrupthound/swoopie,
	"Abyss lurker" = /mob/living/simple_mob/vore/vore_hostile/abyss_lurker,
	"Abyss leaper" = /mob/living/simple_mob/vore/vore_hostile/leaper,
	"Gelatinous cube" = /mob/living/simple_mob/vore/vore_hostile/gelatinous_cube,
	"Gryphon" = /mob/living/simple_mob/vore/gryphon
	))

GLOBAL_LIST_INIT(vr_mob_spawner_options, list(
	"Parrot" = /mob/living/simple_mob/animal/passive/bird/parrot,
	"Rabbit" = /mob/living/simple_mob/vore/rabbit,
	"Cat" = /mob/living/simple_mob/animal/passive/cat,
	"Fox" = /mob/living/simple_mob/animal/passive/fox,
	"Cow" = /mob/living/simple_mob/animal/passive/cow,
	"Dog" = /mob/living/simple_mob/vore/woof,
	"Horse" = /mob/living/simple_mob/vore/horse/big,
	"Hippo" = /mob/living/simple_mob/vore/hippo,
	"Sheep" = /mob/living/simple_mob/vore/sheep,
	"Squirrel" = /mob/living/simple_mob/vore/squirrel,
	"Red panda" = /mob/living/simple_mob/vore/redpanda,
	"Fennec" = /mob/living/simple_mob/vore/fennec,
	"Seagull" =/mob/living/simple_mob/vore/seagull,
	"Corgi" = /mob/living/simple_mob/animal/passive/dog/corgi,
	"Armadillo" = /mob/living/simple_mob/animal/passive/armadillo,
	"Racoon" = /mob/living/simple_mob/animal/passive/raccoon,
	"Goose" = /mob/living/simple_mob/animal/space/goose,
	"Frog" = /mob/living/simple_mob/vore/aggressive/frog,
	"Dire wolf" = /mob/living/simple_mob/vore/wolf/direwolf,
	"Space bumblebee" = /mob/living/simple_mob/vore/bee,
	"Space bear" = /mob/living/simple_mob/animal/space/bear,
	"Otie" = /mob/living/simple_mob/vore/otie,
	"Mutated otie" =/mob/living/simple_mob/vore/otie/feral,
	"Red otie" = /mob/living/simple_mob/vore/otie/red,
	"Giant rat" = /mob/living/simple_mob/vore/aggressive/rat,
	"Giant snake" = /mob/living/simple_mob/vore/aggressive/giant_snake,
	"Hyena" = /mob/living/simple_mob/animal/hyena,
	"Space shark" = /mob/living/simple_mob/animal/space/shark,
	"Shantak" = /mob/living/simple_mob/animal/sif/shantak,
	"Kururak" = /mob/living/simple_mob/animal/sif/kururak,
	"Teppi" = /mob/living/simple_mob/vore/alienanimals/teppi,
	"Slug" = /mob/living/simple_mob/vore/slug,
	"Catslug" = /mob/living/simple_mob/vore/alienanimals/catslug,
	"Weretiger" = /mob/living/simple_mob/vore/weretiger,
	"Dust jumper" = /mob/living/simple_mob/vore/alienanimals/dustjumper,
	"Star treader" = /mob/living/simple_mob/vore/alienanimals/startreader,
	"Space ghost" = /mob/living/simple_mob/vore/alienanimals/spooky_ghost,
	"Space carp" = /mob/living/simple_mob/animal/space/carp,
	"Space jelly fish" = /mob/living/simple_mob/vore/alienanimals/space_jellyfish,
	"Abyss lurker" = /mob/living/simple_mob/vore/vore_hostile/abyss_lurker,
	"Abyss leaper" = /mob/living/simple_mob/vore/vore_hostile/leaper,
	"Gelatinous cube" = /mob/living/simple_mob/vore/vore_hostile/gelatinous_cube,
	"Panther" = /mob/living/simple_mob/vore/aggressive/panther,
	"Lizard man" = /mob/living/simple_mob/vore/aggressive/lizardman,
	"Pakkun" = /mob/living/simple_mob/vore/pakkun,
	"Synx" = /mob/living/simple_mob/animal/synx,
	"Jelly blob" = /mob/living/simple_mob/vore/jelly,
	"Voracious lizard" = /mob/living/simple_mob/vore/aggressive/dino,
	"Baby metroid" = /mob/living/simple_mob/metroid/juvenile/baby,
	"Super metroid" = /mob/living/simple_mob/metroid/juvenile/super,
	"Alpha metroid" = /mob/living/simple_mob/metroid/juvenile/alpha,
	"Gamma metroid" = /mob/living/simple_mob/metroid/juvenile/gamma,
	"Zeta metroid" = /mob/living/simple_mob/metroid/juvenile/zeta,
	"Omega metroid" = /mob/living/simple_mob/metroid/juvenile/omega,
	"Queen metroid" = /mob/living/simple_mob/metroid/juvenile/queen,
	"Xeno hunter" = /mob/living/simple_mob/animal/space/alien,
	"Xeno sentinel" = /mob/living/simple_mob/animal/space/alien/sentinel,
	"Xeno Praetorian" = /mob/living/simple_mob/animal/space/alien/sentinel/praetorian,
	"Xeno queen" = /mob/living/simple_mob/animal/space/alien/queen,
	"Xeno Empress" = /mob/living/simple_mob/animal/space/alien/queen/empress,
	"Xeno Queen Mother" = /mob/living/simple_mob/animal/space/alien/queen/empress/mother,
	"Defanged xeno" = /mob/living/simple_mob/vore/xeno_defanged,
	"Sect drone" = /mob/living/simple_mob/vore/sect_drone,
	"Sect queen" = /mob/living/simple_mob/vore/sect_queen,
	"Deathclaw" = /mob/living/simple_mob/vore/aggressive/deathclaw,
	"Great White Wolf" = /mob/living/simple_mob/vore/greatwolf,
	"Great Black Wolf" = /mob/living/simple_mob/vore/greatwolf/black,
	"Solar grub" = /mob/living/simple_mob/vore/solargrub,
	"Pitcher plant" = /mob/living/simple_mob/vore/pitcher_plant,
	"Red gummy kobold" = /mob/living/simple_mob/vore/candy/redcabold,
	"Blue gummy kobold" = /mob/living/simple_mob/vore/candy/bluecabold,
	"Yellow gummy kobold" = /mob/living/simple_mob/vore/candy/yellowcabold,
	"Marshmellow serpent" = /mob/living/simple_mob/vore/candy/marshmellowserpent,
	"Riftwalker" = /mob/living/simple_mob/vore/demon,
	"Wendigo" = /mob/living/simple_mob/vore/demon/wendigo,
	"Shadekin" = /mob/living/simple_mob/shadekin,
	"Catgirl" = /mob/living/simple_mob/vore/catgirl,
	"Wolfgirl" = /mob/living/simple_mob/vore/wolfgirl,
	"Wolftaur" = /mob/living/simple_mob/vore/wolftaur,
	"Lamia" = /mob/living/simple_mob/vore/lamia,
	"Corrupt hound" = /mob/living/simple_mob/vore/aggressive/corrupthound,
	"Corrupt corrupt hound" = /mob/living/simple_mob/vore/aggressive/corrupthound/prettyboi,
	"SWOOPIE XL" = /mob/living/simple_mob/vore/aggressive/corrupthound/swoopie,
	"Cultist Teshari" = /mob/living/simple_mob/humanoid/cultist/tesh,
	"Burning Mage" = /mob/living/simple_mob/humanoid/cultist/human/bloodjaunt/fireball,
	"Converted" = /mob/living/simple_mob/humanoid/cultist/noodle,
	"Cultist Teshari Mage" = /mob/living/simple_mob/humanoid/cultist/castertesh,
	"Monkey" = /mob/living/carbon/human/monkey,
	"Wolpin" = /mob/living/carbon/human/wolpin,
	"Sparra" = /mob/living/carbon/human/sparram,
	"Saru" = /mob/living/carbon/human/sergallingm,
	"Sobaka" = /mob/living/carbon/human/sharkm,
	"Farwa" = /mob/living/carbon/human/farwa,
	"Neaera" = /mob/living/carbon/human/neaera,
	"Stok" = /mob/living/carbon/human/stok,
	//"Gryphon" = /mob/living/simple_mob/vore/gryphon // Disabled until tested
	))

//global lists I found in various files and moved here for housekeeping
GLOBAL_LIST_EMPTY(stool_cache) //haha stool
GLOBAL_LIST_EMPTY(emotes_by_key)
GLOBAL_LIST_EMPTY(random_maps)
GLOBAL_LIST_EMPTY(map_count)
GLOBAL_LIST_EMPTY(narsie_list)
GLOBAL_LIST_EMPTY(id_card_states)
GLOBAL_LIST_EMPTY(allocated_gamma_loot)
GLOBAL_LIST_EMPTY(semirandom_mob_spawner_decisions)

GLOBAL_LIST_INIT(unique_gamma_loot, list(
	/obj/item/perfect_tele,
	/obj/item/bluespace_harpoon,
	/obj/item/clothing/glasses/thermal/syndi,
	/obj/item/gun/energy/netgun,
	/obj/item/gun/projectile/pirate,
	/obj/item/gun/projectile/dartgun,
	/obj/item/clothing/gloves/black/bloodletter,
	/obj/item/gun/energy/mouseray/metamorphosis
	))

GLOBAL_LIST_INIT(newscaster_standard_feeds, list(/datum/news_announcement/bluespace_research, /datum/news_announcement/lotus_tree, /datum/news_announcement/random_junk,  /datum/news_announcement/food_riots))

GLOBAL_LIST_INIT(changeling_fabricated_clothing, list(
	"w_uniform" = /obj/item/clothing/under/chameleon/changeling,
	"head" = /obj/item/clothing/head/chameleon/changeling,
	"wear_suit" = /obj/item/clothing/suit/chameleon/changeling,
	"shoes" = /obj/item/clothing/shoes/chameleon/changeling,
	"gloves" = /obj/item/clothing/gloves/chameleon/changeling,
	"wear_mask" = /obj/item/clothing/mask/chameleon/changeling,
	"glasses" = /obj/item/clothing/glasses/chameleon/changeling,
	"back" = /obj/item/storage/backpack/chameleon/changeling,
	"belt" = /obj/item/storage/belt/chameleon/changeling,
	"wear_id" = /obj/item/card/id/syndicate/changeling
	))

//  Defines which values mean "on" or "off".
//  This is to make some of the more OP superpowers a larger PITA to activate,
//  and to tell our new DNA datum which values to set in order to turn something
//  on or off.
GLOBAL_ALIST_EMPTY(dna_activity_bounds)

// Used to determine what each block means (admin hax and species stuff on /vg/, mostly)
GLOBAL_ALIST_EMPTY(assigned_blocks)

GLOBAL_LIST_EMPTY(gear_distributed_to)
GLOBAL_LIST_EMPTY(overlay_cache) //cache recent overlays

GLOBAL_LIST_INIT(all_technomancer_gambit_spells, typesof(/obj/item/spell) - list(
	/obj/item/spell,
	/obj/item/spell/gambit,
	/obj/item/spell/projectile,
	/obj/item/spell/aura,
//	/obj/item/spell/insert,
	/obj/item/spell/spawner,
	/obj/item/spell/summon,
	/obj/item/spell/modifier))

GLOBAL_LIST_EMPTY_TYPED(telecomms_list, /obj/machinery/telecomms)

// color-dir-dry
GLOBAL_LIST_EMPTY_TYPED(fluidtrack_cache, /image)

GLOBAL_LIST_INIT_TYPED(sandbag_recipes, /datum/stack_recipe, list( \
	new/datum/stack_recipe("barricade", /obj/structure/barricade/sandbag, 3, time = 5 SECONDS, one_per_turf = 1, on_floor = 1, pass_stack_color = TRUE)))

GLOBAL_LIST_INIT_TYPED(wax_recipes, /datum/stack_recipe, list( \
	new/datum/stack_recipe("candle", /obj/item/flame/candle)))

GLOBAL_LIST_INIT_TYPED(rods_recipes, /datum/stack_recipe, list( \
	new/datum/stack_recipe("grille", /obj/structure/grille, 2, time = 10, one_per_turf = 1, on_floor = 0),
	new/datum/stack_recipe("catwalk", /obj/structure/catwalk, 2, time = 80, one_per_turf = 1, on_floor = 1)))

GLOBAL_LIST_INIT(possible_plants, list(
	"plant-1",
	"plant-10",
	"plant-09",
	"plant-15",
	"plant-13"
))

GLOBAL_LIST_INIT(radio_channels_by_freq, list(
	num2text(PUB_FREQ) = CHANNEL_COMMON,
	num2text(AI_FREQ)  = CHANNEL_AI_PRIVATE,
	num2text(ENT_FREQ) = CHANNEL_ENTERTAINMENT,
	num2text(ERT_FREQ) = CHANNEL_RESPONSE_TEAM,
	num2text(COMM_FREQ)= CHANNEL_COMMAND,
	num2text(ENG_FREQ) = CHANNEL_ENGINEERING,
	num2text(MED_FREQ) = CHANNEL_MEDICAL,
	num2text(MED_I_FREQ)=CHANNEL_MEDICAL_1,
	num2text(BDCM_FREQ) =CHANNEL_BODYCAM,
	num2text(SEC_FREQ) = CHANNEL_SECURITY,
	num2text(SEC_I_FREQ)=CHANNEL_SECURITY_1,
	num2text(SCI_FREQ) = CHANNEL_SCIENCE,
	num2text(SUP_FREQ) = CHANNEL_SUPPLY,
	num2text(SRV_FREQ) = CHANNEL_SERVICE,
	num2text(EXP_FREQ) = CHANNEL_EXPLORATION
	))

GLOBAL_LIST_BOILERPLATE(all_pai_cards, /obj/item/paicard)

// Access check is of the type requires one. These have been carefully selected to avoid allowing the janitor to see channels he shouldn't
GLOBAL_LIST_INIT(default_internal_channels, list(
	num2text(PUB_FREQ) = list(),
	num2text(AI_FREQ)  = list(ACCESS_SYNTH),
	num2text(ENT_FREQ) = list(),
	num2text(ERT_FREQ) = list(ACCESS_CENT_SPECOPS),
	num2text(COMM_FREQ)= list(ACCESS_HEADS),
	num2text(ENG_FREQ) = list(ACCESS_ENGINE_EQUIP, ACCESS_ATMOSPHERICS),
	num2text(MED_FREQ) = list(ACCESS_MEDICAL_EQUIP),
	num2text(MED_I_FREQ)=list(ACCESS_MEDICAL_EQUIP),
	num2text(BDCM_FREQ) =list(ACCESS_SECURITY),
	num2text(SEC_FREQ) = list(ACCESS_SECURITY),
	num2text(SEC_I_FREQ)=list(ACCESS_SECURITY),
	num2text(SCI_FREQ) = list(ACCESS_TOX, ACCESS_ROBOTICS, ACCESS_XENOBIOLOGY),
	num2text(SUP_FREQ) = list(ACCESS_CARGO, ACCESS_MINING_STATION),
	num2text(SRV_FREQ) = list(ACCESS_JANITOR, ACCESS_LIBRARY, ACCESS_HYDROPONICS, ACCESS_BAR, ACCESS_KITCHEN),
	num2text(EXP_FREQ) = list(ACCESS_EXPLORER, ACCESS_PILOT)
))

GLOBAL_LIST_INIT(default_medbay_channels, list(
	num2text(PUB_FREQ) = list(),
	num2text(MED_FREQ) = list(),
	num2text(MED_I_FREQ) = list()
))

GLOBAL_LIST_INIT(device_ringtones, list("beep" = 'sound/machines/twobeep.ogg',
										"boom" = 'sound/effects/explosionfar.ogg',
										"slip" = 'sound/misc/slip.ogg',
										"honk" = 'sound/items/bikehorn.ogg',
										"SKREE" = 'sound/voice/shriek1.ogg',
										// "holy" = 'sound/items/PDA/ambicha4-short.ogg',
										"xeno" = 'sound/voice/hiss1.ogg',
										"dust" = 'sound/effects/supermatter.ogg',
										"spark" = 'sound/effects/sparks4.ogg',
										"rad" = 'sound/items/geiger/high1.ogg',
										"servo" = 'sound/machines/rig/rigservo.ogg',
										// "buh-boop" = 'sound/misc/buh-boop.ogg',
										"trombone" = 'sound/misc/sadtrombone.ogg',
										"whistle" = 'sound/misc/boatswain.ogg',
										"chirp" = 'sound/misc/nymphchirp.ogg',
										"slurp" = 'sound/items/drink.ogg',
										"pwing" = 'sound/items/nif_tone_good.ogg',
										"clack" = 'sound/items/storage/toolbox.ogg',
										"bzzt" = 'sound/misc/null.ogg',	//vibrate mode
										"chimes" = 'sound/misc/notice3.ogg',
										"prbt" = 'sound/voice/prbt.ogg',
										"bark" = 'sound/voice/bark2.ogg',
										"bork" = 'sound/voice/bork.ogg',
										"roark" = 'sound/voice/roarbark.ogg',
										"chitter" = 'sound/voice/moth/moth_chitter.ogg',
										"squish" = 'sound/effects/slime_squish.ogg',
										"bubble"= 'sound/effects/bubbles.ogg',
										"silly" = 'sound/effects/whistle.ogg',
										// "frog" = 'sound/voice/Croak.ogg',
										"peep" = 'sound/voice/peep.ogg',
										"quack" = 'sound/voice/quack.ogg',
										// "ough" = 'sound/misc/ough.ogg',
										"stamp" = 'sound/bureaucracy/stamp.ogg',
										"gnome" = 'sound/items/hooh.ogg',
										"ratchet" = 'sound/items/Ratchet.ogg',
										"tether" = 'sound/items/tinytether.ogg'
										))

GLOBAL_LIST_EMPTY(seen_citizenships)
GLOBAL_LIST_EMPTY(seen_systems)
GLOBAL_LIST_EMPTY(seen_factions)
GLOBAL_LIST_EMPTY(seen_religions)

GLOBAL_LIST_INIT(citizenship_choices, list(
	"Earth",
	"Mars",
	"Sif",
	"Binma",
	"Moghes",
	"Meralar",
	"Qerr'balak"
	))

GLOBAL_LIST_INIT(home_system_choices, list(
	"Virgo-Erigone",
	"Sol",
	"Earth, Sol",
	"Luna, Sol",
	"Mars, Sol",
	"Venus, Sol",
	"Titan, Sol",
	"Toledo, New Ohio",
	"The Pact, Myria",
	"Kishar, Alpha Centauri",
	"Anshar, Alpha Centauri",
	"Heaven Complex, Alpha Centauri",
	"Procyon",
	"Altair",
	"Kara, Vir",
	"Sif, Vir",
	"Brinkburn, Nyx",
	"Binma, Tau Ceti",
	"Qerr'balak, Qerr'valis",
	"Epsilon Ursae Minoris",
	"Meralar, Rarkajar",
	"Tal, Vilous",
	"Menhir, Alat-Hahr",
	"Altam, Vazzend",
	"Uh'Zata, Kelezakata",
	"Moghes, Uuoea-Esa",
	"Xohok, Uuoea-Esa",
	"Varilak, Antares",
	"Sanctorum, Sanctum",
	"Infernum, Sanctum",
	"Abundance in All Things Serene, Beta-Carnelium Ventrum",
	"Jorhul, Barkalis",
	"Shelf Flotilla",
	"Ue-Orsi Flotilla",
	"AH-CV Prosperity",
	"AH-CV Migrant",
	"Altevian Colony Ship"
	))

GLOBAL_LIST_INIT(faction_choices, list(
	"Sol Central",
	"NanoTrasen Incorporated",
	"Hephaestus Industries",
	"Vey-Medical",
	"Zeng-Hu Pharmaceuticals",
	"Ward-Takahashi GMC",
	"Bishop Cybernetics",
	"Morpheus Cyberkinetics",
	"Xion Manufacturing Group",
	"Free Trade Union",
	"Major Bill's Transportation",
	"Ironcrest Transport Group",
	"Grayson Manufactories Ltd.",
	"Aether Atmospherics",
	"Focal Point Energistics",
	"StarFlight Inc.",
	"Oculum Broadcasting Network",
	"Periphery Post",
	"Free Anur Tribune",
	"Centauri Provisions",
	"Einstein Engines",
	"Wulf Aeronautics",
	"Gilthari Exports",
	"Coyote Salvage Corp.",
	"Chimera Genetics Corp.",
	"Independent Pilots Association",
	"Local System Defense Force",
	"United Solar Defense Force",
	"Proxima Centauri Risk Control",
	"HIVE Security",
	"Stealth Assault Enterprises",
	"Teshari Union"
	))

GLOBAL_LIST_EMPTY(antag_faction_choices)	//Should be populated after brainstorming. Leaving as blank in case brainstorming does not occur.

GLOBAL_LIST_INIT(antag_visiblity_choices, list(
	"Hidden",
	"Shared",
	"Known"
	))

GLOBAL_LIST_INIT(religion_choices, list(
	"Unitarianism",
	"Neopaganism",
	"Islam",
	"Christianity",
	"Judaism",
	"Hinduism",
	"Buddhism",
	"Pleromanism",
	"Spectralism",
	"Phact Shintoism",
	"Kishari Faith",
	"Hauler Faith",
	"Nock",
	"Singulitarian Worship",
	"Xilar Qall",
	"Tajr-kii Rarkajar",
	"Agnosticism",
	"Deism",
	"Neo-Moreauism",
	"Orthodox Moreauism"
	))

GLOBAL_LIST_INIT(xenoChemList, list(REAGENT_ID_MUTATIONTOXIN,
						REAGENT_ID_PSILOCYBIN,
						REAGENT_ID_MINDBREAKER,
						REAGENT_ID_IMPEDREZENE,
						REAGENT_ID_CRYPTOBIOLIN,
						REAGENT_ID_BLISS,
						REAGENT_ID_CHLORALHYDRATE,
						REAGENT_ID_STOXIN,
						REAGENT_ID_MUTAGEN,
						REAGENT_ID_LEXORIN,
						REAGENT_ID_PACID,
						REAGENT_ID_CYANIDE,
						REAGENT_ID_PHORON,
						REAGENT_ID_PLASTICIDE,
						REAGENT_ID_AMATOXIN,
						REAGENT_ID_CARBON,
						REAGENT_ID_RADIUM,
						REAGENT_ID_SACID,
						REAGENT_ID_SUGAR,
						REAGENT_ID_KELOTANE,
						REAGENT_ID_DERMALINE,
						REAGENT_ID_ANTITOXIN,
						REAGENT_ID_DEXALIN,
						REAGENT_ID_SYNAPTIZINE,
						REAGENT_ID_ALKYSINE,
						REAGENT_ID_IMIDAZOLINE,
						REAGENT_ID_PERIDAXON,
						REAGENT_ID_REZADONE))

//Chemlist of what was banned in xenobio2. Kept for legacy purposes.
GLOBAL_LIST_INIT(xeno2ChemList, list(REAGENT_ID_INAPROVALINE,
						REAGENT_ID_BICARIDINE,
						REAGENT_ID_DEXALINP,
						REAGENT_ID_TRICORDRAZINE,
						REAGENT_ID_CRYOXADONE,
						REAGENT_ID_CLONEXADONE,
						REAGENT_ID_PARACETAMOL,
						REAGENT_ID_TRAMADOL,
						REAGENT_ID_OXYCODONE,
						REAGENT_ID_RYETALYN,
						REAGENT_ID_HYPERZINE,
						REAGENT_ID_ETHYLREDOXRAZINE,
						REAGENT_ID_HYRONALIN,
						REAGENT_ID_ARITHRAZINE,
						REAGENT_ID_SPACEACILLIN,
						REAGENT_ID_STERILIZINE,
						REAGENT_ID_LEPORAZINE,
						REAGENT_ID_METHYLPHENIDATE,
						REAGENT_ID_CITALOPRAM,
						REAGENT_ID_PAROXETINE,
						REAGENT_ID_MACROCILLIN,
						REAGENT_ID_MICROCILLIN,
						REAGENT_ID_NORMALCILLIN,
						REAGENT_ID_SIZEOXADONE,
						REAGENT_ID_ICKYPAK,
						REAGENT_ID_UNSORBITOL,
						REAGENT_ID_TOXIN,
						REAGENT_ID_CARPOTOXIN,
						REAGENT_ID_POTASSIUMCHLORIDE,
						REAGENT_ID_POTASSIUMCHLOROPHORIDE,
						REAGENT_ID_ZOMBIEPOWDER,
						REAGENT_ID_FERTILIZER,
						REAGENT_ID_EZNUTRIENT,
						REAGENT_ID_LEFT4ZED,
						REAGENT_ID_ROBUSTHARVEST,
						REAGENT_ID_PLANTBGONE,
						REAGENT_ID_SEROTROTIUM,
						REAGENT_ID_NICOTINE,
						REAGENT_ID_URANIUM,
						REAGENT_ID_SILVER,
						REAGENT_ID_GOLD,
						REAGENT_ID_ADRENALINE,
						REAGENT_ID_HOLYWATER,
						REAGENT_ID_AMMONIA,
						REAGENT_ID_DIETHYLAMINE,
						REAGENT_ID_FLUOROSURFACTANT,
						REAGENT_ID_FOAMINGAGENT,
						REAGENT_ID_THERMITE,
						REAGENT_ID_CLEANER,
						REAGENT_ID_LUBE,
						REAGENT_ID_SILICATE,
						REAGENT_ID_GLYCEROL,
						REAGENT_ID_COOLANT,
						REAGENT_ID_LUMINOL,
						REAGENT_ID_NUTRIMENT,
						REAGENT_ID_CORNOIL,
						REAGENT_ID_LIPOZINE,
						REAGENT_ID_SODIUMCHLORIDE,
						REAGENT_ID_FROSTOIL,
						REAGENT_ID_CAPSAICIN,
						REAGENT_ID_CONDENSEDCAPSAICIN,
						REAGENT_ID_NEUROTOXIN))

//keep synced with the defines BE_* in setup.dm --rastaf
//some autodetection here.
//Change these to 0 if the equivalent mode is disabled for whatever reason!
GLOBAL_LIST_INIT(special_roles, list(
	"traitor" = 0,										// 0
	"operative" = 0,									// 1
	"changeling" = 0,									// 2
	"wizard" = 0,										// 3
	"malf AI" = 0,										// 4
	"revolutionary" = 0,								// 5
	"alien candidate" = 0,								// 6
	"positronic brain" = 1,								// 7
	"cultist" = 0,										// 8
	"renegade" = 0,										// 9
	"ninja" = 0,										// 10
	"raider" = 0,										// 11
	"diona" = 0,										// 12
	"loyalist" = 0,										// 13
	"pAI" = 1,											// 14
	"lost drone" = 1,									// 15
	"maint critter" = 1,								// 16
	"corgi" = 1,										// 17
	"cursed sword" = 1,									// 18
	"ship survivor" = 1,								// 19
))

GLOBAL_LIST_INIT(maint_mob_pred_options, list(
	"Rabbit" = /mob/living/simple_mob/vore/rabbit,
	"Red Panda" = /mob/living/simple_mob/vore/redpanda,
	"Fennec" = /mob/living/simple_mob/vore/fennec,
	"Fennix" = /mob/living/simple_mob/vore/fennix,
	"Fox" = /mob/living/simple_mob/animal/passive/fox,
	"Syndi-Fox" = /mob/living/simple_mob/animal/passive/fox/syndicate,
	"Raccoon" = /mob/living/simple_mob/animal/passive/raccoon,
	"Cat" = /mob/living/simple_mob/animal/passive/cat,
	"Space Bumblebee" = /mob/living/simple_mob/vore/bee,
	"Space Bear" = /mob/living/simple_mob/animal/space/bear,
	"Voracious Lizard" = /mob/living/simple_mob/vore/aggressive/dino,
	"Giant Frog" = /mob/living/simple_mob/vore/aggressive/frog,
	"Giant Rat" = /mob/living/simple_mob/vore/aggressive/rat,
	"Jelly Blob" = /mob/living/simple_mob/vore/jelly,
	"Wolf" = /mob/living/simple_mob/vore/wolf,
	"Dire Wolf" = /mob/living/simple_mob/vore/wolf/direwolf,
	"Large Dog" = /mob/living/simple_mob/vore/wolf/direwolf/dog,
	"Juvenile Solargrub" = /mob/living/simple_mob/vore/solargrub,
	"Sect Queen" = /mob/living/simple_mob/vore/sect_queen,
	"Sect Drone" = /mob/living/simple_mob/vore/sect_drone,
	"Defanged Xenomorph" = /mob/living/simple_mob/vore/xeno_defanged,
	"Panther" = /mob/living/simple_mob/vore/aggressive/panther,
	"Giant Snake" = /mob/living/simple_mob/vore/aggressive/giant_snake,
	"Deathclaw" = /mob/living/simple_mob/vore/aggressive/deathclaw,
	"Otie" = /mob/living/simple_mob/vore/otie,
	"Chubby Otie" = /mob/living/simple_mob/vore/otie/friendly/chubby,
	"Mutated Otie" = /mob/living/simple_mob/vore/otie/feral,
	"Chubby Mutated Otie" = /mob/living/simple_mob/vore/otie/feral/chubby,
	"Red Otie" = /mob/living/simple_mob/vore/otie/red,
	"Chubby Red Otie" = /mob/living/simple_mob/vore/otie/red/chubby,
	"Corrupt Hound" = /mob/living/simple_mob/vore/aggressive/corrupthound,
	"Corrupt Corrupt Hound" = /mob/living/simple_mob/vore/aggressive/corrupthound/prettyboi,
	"Hunter Giant Spider" = /mob/living/simple_mob/animal/giant_spider/hunter,
	"Lurker Giant Spider" = /mob/living/simple_mob/animal/giant_spider/lurker,
	"Pepper Giant Spider" = /mob/living/simple_mob/animal/giant_spider/pepper,
	"Thermic Giant Spider" = /mob/living/simple_mob/animal/giant_spider/thermic,
	"Webslinger Giant Spider" = /mob/living/simple_mob/animal/giant_spider/webslinger,
	"Frost Giant Spider" = /mob/living/simple_mob/animal/giant_spider/frost,
	"Nurse Giant Spider" = /mob/living/simple_mob/animal/giant_spider/nurse/eggless,
	"Giant Spider Queen" = /mob/living/simple_mob/animal/giant_spider/nurse/queen/eggless,
	"Red Dragon" = /mob/living/simple_mob/vore/aggressive/dragon,
	"Phoron Dragon" = /mob/living/simple_mob/vore/aggressive/dragon/virgo3b,
	"Space Dragon" = /mob/living/simple_mob/vore/aggressive/dragon/space,
	"Crypt Drake" = /mob/living/simple_mob/vore/cryptdrake,
	"Weretiger" = /mob/living/simple_mob/vore/weretiger,
	"Catslug" = /mob/living/simple_mob/vore/alienanimals/catslug,
	"Squirrel" = /mob/living/simple_mob/vore/squirrel/big,
	"Pakkun" =/mob/living/simple_mob/vore/pakkun,
	"Snapdragon" =/mob/living/simple_mob/vore/pakkun/snapdragon,
	"Sand pakkun" = /mob/living/simple_mob/vore/pakkun/sand,
	"Fire pakkun" = /mob/living/simple_mob/vore/pakkun/fire,
	"Amethyst pakkun" = /mob/living/simple_mob/vore/pakkun/purple,
	"Raptor" = /mob/living/simple_mob/vore/raptor,
	"Scel (Orange)" = /mob/living/simple_mob/vore/scel/orange,
	"Scel (Blue)" = /mob/living/simple_mob/vore/scel/blue,
	"Scel (Purple)" = /mob/living/simple_mob/vore/scel/purple,
	"Scel (Red)" = /mob/living/simple_mob/vore/scel/red,
	"Scel (Green)" = /mob/living/simple_mob/vore/scel/green,
	"Cave Stalker" = /mob/living/simple_mob/vore/stalker,
	"Kelpie" = /mob/living/simple_mob/vore/horse/kelpie,
	"Scrubble" = /mob/living/simple_mob/vore/scrubble,
	"Sonadile" = /mob/living/simple_mob/vore/sonadile,
	"kururak" = /mob/living/simple_mob/animal/sif/kururak,
	"Statue of Temptation" = /mob/living/simple_mob/vore/devil,
	"Meowl" = /mob/living/simple_mob/vore/meowl,
	"Abyss Leaper" = /mob/living/simple_mob/vore/vore_hostile/leaper,
	"Abyss Lurker" = /mob/living/simple_mob/vore/vore_hostile/abyss_lurker,
	"Horse" = /mob/living/simple_mob/vore/horse/big,
	"Lizardman" = /mob/living/simple_mob/vore/aggressive/lizardman,
	"Giant Lab Rat" = /mob/living/simple_mob/vore/aggressive/rat/labrat,
	"Hyena" = /mob/living/simple_mob/animal/hyena,
	"Xenomorph Hunter" = /mob/living/simple_mob/xeno_ch/hunter,
	"Xenomorph Sentinel" = /mob/living/simple_mob/xeno_ch/sentinel,
	"Xenomorph Queen" = /mob/living/simple_mob/xeno_ch/queen,
	"Xenomorph Maid Queen" = /mob/living/simple_mob/xeno_ch/queen/maid,
	"Corrupt JaniHound" = /mob/living/simple_mob/vore/retaliate/corrupthound/janihound,
	"Corrupt Old JaniHound" = /mob/living/simple_mob/vore/retaliate/corrupthound/janihound/old,
	"Corrupt MediHound" = /mob/living/simple_mob/vore/retaliate/corrupthound/janihound/medihound,
	"Lesser Large Dragon" = /mob/living/simple_mob/vore/bigdragon/friendly/maintpred,
	"Zorgoia" = /mob/living/simple_mob/vore/zorgoia,
	"Gryphon" = /mob/living/simple_mob/vore/gryphon,
	"Synx" = /mob/living/simple_mob/animal/synx,
	"Reindeer" = /mob/living/simple_mob/vore/reindeer,
	"Lion/Lioness" = /mob/living/simple_mob/vore/retaliate/lion,
	"Swoopie XL" = /mob/living/simple_mob/vore/aggressive/corrupthound/swoopie,
	"Teppie" = /mob/living/simple_mob/vore/alienanimals/teppi,
	"Frostlit Lamp" = /mob/living/simple_mob/animal/passive/gaslamp/snow,
	"Voidwalker" = /mob/living/simple_mob/vore/demon,
	"Super Metroid" = /mob/living/simple_mob/metroid/juvenile/super,
	"Space Carp" = /mob/living/simple_mob/animal/space/carp,
	"Great White Carp" = /mob/living/simple_mob/animal/space/carp/large/huge/vorny,
	"Giant Bat" = /mob/living/simple_mob/vore/bat
	))

// GLOB.alldirs in global.dm is the same list of directions, but since
//  the specific order matters to get a usable icon_state, it is
//  copied here so that, in the unlikely case that GLOB.alldirs is changed, transit_tube.dm
//  continues to work.
GLOBAL_LIST_INIT(tube_dir_list, list(
	NORTH,
	SOUTH,
	EAST,
	WEST,
	NORTHEAST,
	NORTHWEST,
	SOUTHEAST,
	SOUTHWEST))

GLOBAL_LIST_EMPTY(direction_table)

GLOBAL_LIST_INIT(valid_bloodreagents, list("default",REAGENT_ID_IRON,REAGENT_ID_COPPER,REAGENT_ID_PHORON,REAGENT_ID_SILVER,REAGENT_ID_GOLD,REAGENT_ID_SLIMEJELLY))	//allowlist-based so people don't make their blood restored by alcohol or something really silly. use reagent IDs!

GLOBAL_LIST_EMPTY(monitor_states)

GLOBAL_LIST_EMPTY(random_junk)
GLOBAL_LIST_EMPTY(random_junk_)
GLOBAL_LIST_EMPTY(random_useful_)
GLOBAL_LIST_INIT(valid_bloodtypes, list("A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"))

//Some simple descriptors for breaches. Global because lazy, TODO: work out a better way to do this.

GLOBAL_LIST_INIT(breach_brute_descriptors, list(
	"tiny puncture",
	"ragged tear",
	"large split",
	"huge tear",
	"gaping wound"
	))

GLOBAL_LIST_INIT(breach_burn_descriptors, list(
	"small burn",
	"melted patch",
	"sizable burn",
	"large scorched area",
	"huge scorched area"
	))

GLOBAL_LIST_EMPTY(paikeys)

GLOBAL_LIST_EMPTY(pai_software_by_key)
GLOBAL_LIST_EMPTY(default_pai_software)
GLOBAL_LIST_INIT(pai_emotions, list(
		"Neutral" = 1,
		"What" = 2,
		"Happy" = 3,
		"Cat" = 4,
		"Extremely Happy" = 5,
		"Face" = 6,
		"Laugh" = 7,
		"Sad" = 8,
		"Angry" = 9,
		"Silly" = 10,
		"Nose" = 11,
		"Smirk" = 12,
		"Exclamation Points" = 13,
		"Question Mark" = 14,
		"Blank" = 15,
		"Off" = 16
	))

//Sure I could spend all day making wacky overlays for all of the different forms
//but quite simply most of these sprites aren't made for that, and I'd rather just make new ones
//the birds especially! Just naw. If someone else wants to mess with 12x4 frames of animation where
//most of the pixels are different kinds of green and tastefully translate that to whitescale
//they can have fun with that! I not doing it!
GLOBAL_LIST_INIT(allows_eye_color, list(
	"pai-repairbot",
	"pai-typezero",
	"pai-bat",
	"pai-butterfly",
	"pai-mouse",
	"pai-monkey",
	"pai-raccoon",
	"pai-cat",
	"rat",
	"panther",
	"pai-bear",
	"pai-fen",
	"cyberelf",
	"teppi",
	"catslug",
	"car",
	"typeone",
	"13",
	"pai-raptor",
	"pai-diredog",
	"pai-horse_lune",
	"pai-horse_soleil",
	"pai-pdragon",
	"pai-protodog"
	))


GLOBAL_LIST_EMPTY(entopic_images)
GLOBAL_LIST_EMPTY(entopic_users)

GLOBAL_LIST_EMPTY(alt_farmanimals)

GLOBAL_ALIST_INIT(available_recipes, build_kitchen_recipes()) //List of all recipies. THIS MUST COME FIRST before acceptable_items and acceptable_reagents because it is used to build those lists.
GLOBAL_LIST_INIT(acceptable_items, build_kitchen_items()) // List of the items you can put in
GLOBAL_LIST_INIT(acceptable_reagents, build_kitchen_reagents()) // List of the reagents you can put in


GLOBAL_LIST_INIT(all_ui_styles, list(
	"Midnight"     = 'icons/mob/screen/midnight.dmi',
	"Orange"       = 'icons/mob/screen/orange.dmi',
	"old"          = 'icons/mob/screen/old.dmi',
	"White"        = 'icons/mob/screen/white.dmi',
	"old-noborder" = 'icons/mob/screen/old-noborder.dmi',
	"minimalist"   = 'icons/mob/screen/minimalist.dmi',
	"Hologram"     = 'icons/mob/screen/holo.dmi'
	))

GLOBAL_LIST_INIT(all_ui_styles_robot, list(
	"Midnight"     = 'icons/mob/screen1_robot.dmi',
	"Orange"       = 'icons/mob/screen1_robot.dmi',
	"old"          = 'icons/mob/screen1_robot.dmi',
	"White"        = 'icons/mob/screen1_robot.dmi',
	"old-noborder" = 'icons/mob/screen1_robot.dmi',
	"minimalist"   = 'icons/mob/screen1_robot_minimalist.dmi',
	"Hologram"     = 'icons/mob/screen1_robot_minimalist.dmi'
	))

GLOBAL_LIST_INIT(all_tooltip_styles, list(
	"Midnight",		//Default for everyone is the first one,
	"Plasmafire",
	"Retro",
	"Slimecore",
	"Operative",
	"Clockwork"
	))

GLOBAL_LIST_EMPTY(gun_choices)

GLOBAL_ALIST_INIT(severity_to_string, list(
	/* EVENT_LEVEL_MUNDANE = */ "Mundane",
	/* EVENT_LEVEL_MODERATE = */ "Moderate",
	/* EVENT_LEVEL_MAJOR = */ "Major"
	))

//Some global icons for the examine tab to use to display some item properties.
GLOBAL_LIST_INIT(description_icons, list(
	"melee_armor" = image(icon='icons/mob/screen1_stats.dmi',icon_state="melee_protection"),
	"bullet_armor" = image(icon='icons/mob/screen1_stats.dmi',icon_state="bullet_protection"),
	"laser_armor" = image(icon='icons/mob/screen1_stats.dmi',icon_state="laser_protection"),
	"energy_armor" = image(icon='icons/mob/screen1_stats.dmi',icon_state="energy_protection"),
	"bomb_armor" = image(icon='icons/mob/screen1_stats.dmi',icon_state="bomb_protection"),
	"radiation_armor" = image(icon='icons/mob/screen1_stats.dmi',icon_state="radiation_protection"),
	"biohazard_armor" = image(icon='icons/mob/screen1_stats.dmi',icon_state="biohazard_protection"),

	"offhand" = image(icon='icons/mob/screen1_stats.dmi',icon_state="offhand"),

	"welder" = image(icon='icons/obj/tools.dmi',icon_state="welder"),
	"wirecutters" = image(icon='icons/obj/tools.dmi',icon_state="cutters"),
	"screwdriver" = image(icon='icons/obj/tools.dmi',icon_state="screwdriver"),
	"wrench" = image(icon='icons/obj/tools.dmi',icon_state="wrench"),
	"crowbar" = image(icon='icons/obj/tools.dmi',icon_state="crowbar"),
	"multitool" = image(icon='icons/obj/device.dmi',icon_state="multitool"),
	"cable coil" = image(icon='icons/obj/power.dmi',icon_state="coil"),

	"metal sheet" = image(icon='icons/obj/items.dmi',icon_state="sheet-metal"),
	"plasteel sheet" = image(icon='icons/obj/items.dmi',icon_state="sheet-plasteel"),

	"air tank" = image(icon='icons/obj/tank.dmi',icon_state="oxygen"),
	"connector" = image(icon='icons/obj/pipes.dmi',icon_state="connector"),

	"stunbaton" = image(icon='icons/obj/weapons.dmi',icon_state="stunbaton_active"),
	"slimebaton" = image(icon='icons/obj/weapons.dmi',icon_state="slimebaton_active"),

	"power cell" = image(icon='icons/obj/power_cells.dmi',icon_state="b_st"),
	"device cell" = image(icon='icons/obj/power_cells.dmi',icon_state="m_st"),
	"weapon cell" = image(icon='icons/obj/power_cells.dmi',icon_state="m_sup"),

	"hatchet" = image(icon='icons/obj/weapons.dmi',icon_state="hatchet"),
	))

// TODO - Optimize this into numerics if this ends up working out
GLOBAL_LIST_INIT(MOVE_KEY_MAPPINGS, list(
	"North" = NORTH_KEY,
	"South" = SOUTH_KEY,
	"East" = EAST_KEY,
	"West" = WEST_KEY,
	"W" = W_KEY,
	"A" = A_KEY,
	"S" = S_KEY,
	"D" = D_KEY,
	"Shift" = SHIFT_KEY,
	"Ctrl" = CTRL_KEY,
	"Alt" = ALT_KEY,
))

GLOBAL_LIST_EMPTY(total_extraction_beacons)

GLOBAL_LIST_INIT(possible_ghost_sprites, list(
	"Clear" = "blank",
	"Green Blob" = "otherthing",
	"Bland" = "ghost",
	"Robed-B" = "ghost1",
	"Robed-BAlt" = "ghost2",
	"King" = "ghostking",
	"Shade" = "shade",
	"Hecate" = "ghost-narsie",
	"Glowing Statue" = "armour",
	"Artificer" = "artificer",
	"Behemoth" = "behemoth",
	"Harvester" = "harvester",
	"Wraith" = "wraith",
	"Viscerator" = "viscerator",
	"Corgi" = "corgi",
	"Tamaskan" = "tamaskan",
	"Black Cat" = "blackcat",
	"Lizard" = "lizard",
	"Goat" = "goat",
	"Space Bear" = "bear",
	"Bats" = "bat",
	"Chicken" = "chicken_white",
	"Parrot"= "parrot_fly",
	"Goose" = "goose",
	"Penguin" = "penguin",
	"Brown Crab" = "crab",
	"Gray Crab" = "evilcrab",
	"Trout" = "trout-swim",
	"Salmon" = "salmon-swim",
	"Pike" = "pike-swim",
	"Koi" = "koi-swim",
	"Carp" = "carp",
	"Red Robes" = "robe_red",
	"Faithless" = "faithless",
	"Shadowform" = "forgotten",
	"Dark Ethereal" = "bloodguardian",
	"Holy Ethereal" = "lightguardian",
	"Red Elemental" = "magicRed",
	"Blue Elemental" = "magicBlue",
	"Pink Elemental" = "magicPink",
	"Orange Elemental" = "magicOrange",
	"Green Elemental" = "magicGreen",
	"Daemon" = "daemon",
	"Guard Spider" = "guard",
	"Hunter Spider" = "hunter",
	"Nurse Spider" = "nurse",
	"Rogue Drone" = "drone",
	"ED-209" = "ed209",
	"Beepsky" = "secbot"
	))

GLOBAL_LIST_EMPTY(sparring_attack_cache)

GLOBAL_LIST_EMPTY(protean_abilities)

//PAI stuff
GLOBAL_LIST_INIT(possible_say_verbs, list(
	"Robotic" = list("states","declares","queries"),
	"Natural" = list("says","yells","asks"),
	"Beep" = list("beeps","beeps loudly","boops"),
	"Chirp" = list("chirps","chirrups","cheeps"),
	"Feline" = list("purrs","yowls","meows"),
	"Canine" = list("yaps","barks","woofs"),
	"Rodent" = list("squeaks", "SQUEAKS", "sqiks")
	))

//Borg modules
GLOBAL_LIST_INIT(robot_modules, list(
	"Standard"		= /obj/item/robot_module/robot/standard,
	"Service" 		= /obj/item/robot_module/robot/clerical/butler,
	"Clerical" 		= /obj/item/robot_module/robot/clerical/general,
	"Clown"			= /obj/item/robot_module/robot/clerical/honkborg,
	"Command"		= /obj/item/robot_module/robot/chound,
	"Research" 		= /obj/item/robot_module/robot/research,
	"Miner" 		= /obj/item/robot_module/robot/miner,
	"Crisis" 		= /obj/item/robot_module/robot/medical/crisis,
	"Surgeon" 		= /obj/item/robot_module/robot/medical/surgeon,
	"Security" 		= /obj/item/robot_module/robot/security/general,
	"Combat" 		= /obj/item/robot_module/robot/security/combat,
	"Exploration"	= /obj/item/robot_module/robot/exploration,
	"Engineering"	= /obj/item/robot_module/robot/engineering,
	"Janitor" 		= /obj/item/robot_module/robot/janitor,
	"Gravekeeper"	= /obj/item/robot_module/robot/malf/gravekeeper,
	"Lost"			= /obj/item/robot_module/robot/malf/lost,
	"Protector" 	= /obj/item/robot_module/robot/syndicate/protector,
	"Mechanist" 	= /obj/item/robot_module/robot/syndicate/mechanist,
	"Combat Medic"	= /obj/item/robot_module/robot/syndicate/combat_medic,
	"Ninja" 		= /obj/item/robot_module/robot/syndicate/ninja,
	))


//Xenoarch stuff
/// <summary>
/// This is a list of what the depth_scanner can show, depending on what get_responsive_reagent returns below.
/// </summary>
GLOBAL_LIST_INIT(responsive_carriers, list(
	REAGENT_ID_CARBON,
	REAGENT_ID_POTASSIUM,
	REAGENT_ID_HYDROGEN,
	REAGENT_ID_NITROGEN,
	REAGENT_BLOOD,
	REAGENT_ID_MERCURY,
	REAGENT_ID_IRON,
	REAGENT_ID_PHORON))

/// <summary>
/// This is a list of what the depth_scanner shows the user. In order with the above list.
/// </summary>
/// <example>
/// If the get_responsive_reagent returns 'REAGENT_ID_CARBON' it will show up to the user as "Trace organic cells"
/// If the get_responsive_reagent returns "REAGENT_ID_CHLORINE" it will show up to the user as "Metamorphic/igneous rock composite"
/// </example>
GLOBAL_LIST_INIT(finds_as_strings, list(
	"Trace organic cells", 							//Carbon
	"Long exposure particles", 						//Potassium
	"Trace water particles", 						//Hydrogen
	"Crystalline structures", 						//Nitrogen
	"Abnormal energy signatures",					//Occult
	"Metallic derivative", 							//Mercury
	"Metallic composite", 							//Iron
	"Anomalous material")) 							//Phoron


//tgui law manager
GLOBAL_LIST_EMPTY_TYPED(admin_laws, /datum/ai_laws)
GLOBAL_LIST_EMPTY_TYPED(player_laws, /datum/ai_laws)

//shield_gen/external
GLOBAL_LIST_INIT(external_shield_gen_blockedturfs,  list(
	/turf/space,
	/turf/simulated/floor/outdoors,
))

//machinery/shieldgen
GLOBAL_LIST_INIT(shieldgen_blockedturfs,  list(
	/turf/space,
	/turf/simulated/floor/outdoors,
))

//Reagent Grinders
// Don't need a new list for every grinder in the game
GLOBAL_LIST_INIT(sheet_reagents, list( //have a number of reagents divisible by REAGENTS_PER_SHEET (default 20) unless you like decimals.
	/obj/item/stack/material/plastic = list(REAGENT_ID_CARBON,REAGENT_ID_CARBON,REAGENT_ID_OXYGEN,REAGENT_ID_CHLORINE,REAGENT_ID_SULFUR),
	/obj/item/stack/material/copper = list(REAGENT_ID_COPPER),
	/obj/item/stack/material/graphite = list(REAGENT_ID_CARBON),
	/obj/item/stack/material/aluminium = list(REAGENT_ID_ALUMINIUM),
	/obj/item/stack/material/diamond = list(REAGENT_ID_CARBON),
	/obj/item/stack/material/durasteel = list(REAGENT_ID_IRON,REAGENT_ID_IRON,REAGENT_ID_CARBON,REAGENT_ID_CARBON,REAGENT_ID_PLATINUM),
	/obj/item/stack/material/wax = list(REAGENT_ID_ETHANOL,REAGENT_ID_TRIGLYCERIDE),
	/obj/item/stack/material/iron = list(REAGENT_ID_IRON),
	/obj/item/stack/material/phoron = list(REAGENT_ID_PHORON),
	/obj/item/stack/material/gold = list(REAGENT_ID_GOLD),
	/obj/item/stack/material/silver = list(REAGENT_ID_SILVER),
	/obj/item/stack/material/platinum = list(REAGENT_ID_PLATINUM),
	/obj/item/stack/material/osmium = list(REAGENT_ID_PLATINUM), // This should be fixed someday
	/obj/item/stack/material/steel = list(REAGENT_ID_IRON, REAGENT_ID_CARBON),
	/obj/item/stack/material/plasteel = list(REAGENT_ID_IRON, REAGENT_ID_IRON, REAGENT_ID_CARBON, REAGENT_ID_CARBON, REAGENT_ID_PLATINUM), //8 iron, 8 carbon, 4 platinum,
	/obj/item/stack/material/sandstone = list(REAGENT_ID_SILICON, REAGENT_ID_OXYGEN),
	/obj/item/stack/material/marble = list(REAGENT_ID_CALCIUM),
	/obj/item/stack/material/titanium = list(REAGENT_ID_ALUMINIUM),
	/obj/item/stack/material/lead = list(REAGENT_ID_LEAD),
	// Nuclear
	/obj/item/stack/material/mhydrogen = list(REAGENT_ID_HYDROGEN),
	/obj/item/stack/material/deuterium = list(REAGENT_ID_HYDROGEN),
	/obj/item/stack/material/tritium = list(REAGENT_ID_HYDROGEN),
	/obj/item/stack/material/uranium = list(REAGENT_ID_URANIUM),
	/obj/item/stack/material/supermatter = list(REAGENT_ID_SUPERMATTER),
	// Misc
	/obj/item/stack/material/snow = list(REAGENT_ID_WATER,REAGENT_ID_ICE),
	/obj/item/stack/tile/grass = list(REAGENT_ID_CARBON,REAGENT_ID_NITROGEN,REAGENT_ID_NITROGEN,REAGENT_ID_PHOSPHORUS,REAGENT_ID_PHOSPHORUS),
	/obj/item/stack/material/leather = list(REAGENT_ID_CARBON,REAGENT_ID_CARBON,REAGENT_ID_PROTEIN,REAGENT_ID_PROTEIN,REAGENT_ID_TRIGLYCERIDE),
	/obj/item/stack/material/cloth = list(REAGENT_ID_CARBON,REAGENT_ID_CARBON,REAGENT_ID_CARBON,REAGENT_ID_PROTEIN,REAGENT_ID_SODIUM),
	/obj/item/stack/material/fiber = list(REAGENT_ID_CARBON,REAGENT_ID_CARBON,REAGENT_ID_CARBON,REAGENT_ID_PROTEIN,REAGENT_ID_SODIUM),
	/obj/item/stack/material/fur = list(REAGENT_ID_CARBON,REAGENT_ID_CARBON,REAGENT_ID_CARBON,REAGENT_ID_SULFUR,REAGENT_ID_SODIUM),
	/obj/item/stack/material/algae = list(REAGENT_ID_CARBON,REAGENT_ID_NITROGEN,REAGENT_ID_NITROGEN,REAGENT_ID_PHOSPHORUS,REAGENT_ID_PHOSPHORUS),
	/obj/item/stack/material/algae/ten = list(REAGENT_ID_CARBON,REAGENT_ID_NITROGEN,REAGENT_ID_NITROGEN,REAGENT_ID_PHOSPHORUS,REAGENT_ID_PHOSPHORUS), // Just spawns with 10, is the same as normal one
	/obj/item/stack/material/concrete = list(REAGENT_ID_SILICATE, REAGENT_ID_CALCIUM),
	/obj/item/stack/material/cardboard = list(REAGENT_ID_WOODPULP),
	// Woods
	/obj/item/stack/material/wood = list(REAGENT_ID_CARBON,REAGENT_ID_WOODPULP,REAGENT_ID_NITROGEN,REAGENT_ID_POTASSIUM,REAGENT_ID_SODIUM),
	/obj/item/stack/material/wood/sif = list(REAGENT_ID_CARBON,REAGENT_ID_WOODPULP,REAGENT_ID_NITROGEN,REAGENT_ID_POTASSIUM,REAGENT_ID_SODIUM),
	/obj/item/stack/material/wood/hard = list(REAGENT_ID_CARBON,REAGENT_ID_WOODPULP,REAGENT_ID_NITROGEN,REAGENT_ID_POTASSIUM,REAGENT_ID_SODIUM),
	// Hull
	/obj/item/stack/material/steel/hull = list(REAGENT_ID_IRON, REAGENT_ID_CARBON),
	/obj/item/stack/material/plasteel/hull = list(REAGENT_ID_IRON, REAGENT_ID_IRON, REAGENT_ID_CARBON, REAGENT_ID_CARBON, REAGENT_ID_PLATINUM),
	/obj/item/stack/material/plastitanium/hull = list(REAGENT_ID_TITANIUM, REAGENT_ID_SILICON, REAGENT_ID_IRON, REAGENT_ID_CARBON, REAGENT_ID_PLATINUM),
	/obj/item/stack/material/durasteel/hull = list(REAGENT_ID_IRON,REAGENT_ID_IRON,REAGENT_ID_CARBON,REAGENT_ID_CARBON,REAGENT_ID_PLATINUM),
	// Glass
	/obj/item/stack/material/glass = list(REAGENT_ID_SILICON),
	/obj/item/stack/material/glass/reinforced = list(REAGENT_ID_SILICON,REAGENT_ID_SILICON,REAGENT_ID_SILICON,REAGENT_ID_IRON,REAGENT_ID_CARBON),
	/obj/item/stack/material/glass/phoronglass = list(REAGENT_ID_PLATINUM, REAGENT_ID_SILICON, REAGENT_ID_SILICON, REAGENT_ID_SILICON), //5 platinum, 15 silicon,
	/obj/item/stack/material/glass/phoronrglass = list(REAGENT_ID_SILICON,REAGENT_ID_SILICON,REAGENT_ID_SILICON,REAGENT_ID_PHORON,REAGENT_ID_PHORON),
	/obj/item/stack/material/glass/titanium = list(REAGENT_ID_TITANIUM, REAGENT_ID_SILICON),
	/obj/item/stack/material/glass/plastitanium = list(REAGENT_ID_TITANIUM, REAGENT_ID_SILICON, REAGENT_ID_IRON, REAGENT_ID_CARBON, REAGENT_ID_PLATINUM),
	// Rods
	/obj/item/stack/rods = list(REAGENT_ID_IRON, REAGENT_ID_CARBON), // 2 per sheet of steel
	/obj/item/stack/material/plasteel/rebar = list(REAGENT_ID_IRON, REAGENT_ID_IRON, REAGENT_ID_CARBON, REAGENT_ID_CARBON, REAGENT_ID_PLATINUM), // Only makes 1 per sheet of plasteel!
	// Logs
	/obj/item/stack/material/stick = list(REAGENT_ID_CARBON,REAGENT_ID_WOODPULP,REAGENT_ID_NITROGEN,REAGENT_ID_POTASSIUM,REAGENT_ID_SODIUM),
	/obj/item/stack/material/stick/fivestack = list(REAGENT_ID_CARBON,REAGENT_ID_WOODPULP,REAGENT_ID_NITROGEN,REAGENT_ID_POTASSIUM,REAGENT_ID_SODIUM), // Just spawns with 5, same as normal one
	/obj/item/stack/material/log = list(REAGENT_ID_CARBON,REAGENT_ID_WOODPULP,REAGENT_ID_NITROGEN,REAGENT_ID_POTASSIUM,REAGENT_ID_SODIUM),
	/obj/item/stack/material/log/hard = list(REAGENT_ID_CARBON,REAGENT_ID_WOODPULP,REAGENT_ID_NITROGEN,REAGENT_ID_POTASSIUM,REAGENT_ID_SODIUM),
	/obj/item/stack/material/log/sif = list(REAGENT_ID_CARBON,REAGENT_ID_WOODPULP,REAGENT_ID_NITROGEN,REAGENT_ID_POTASSIUM,REAGENT_ID_SODIUM),
	))

GLOBAL_LIST_INIT(ore_reagents, list( //have a number of reageents divisible by REAGENTS_PER_ORE (default 20) unless you like decimals.
	/obj/item/ore/glass = list(REAGENT_ID_SILICON),
	/obj/item/ore/iron = list(REAGENT_ID_IRON),
	/obj/item/ore/coal = list(REAGENT_ID_CARBON),
	/obj/item/ore/phoron = list(REAGENT_ID_PHORON),
	/obj/item/ore/silver = list(REAGENT_ID_SILVER),
	/obj/item/ore/gold = list(REAGENT_ID_GOLD),
	/obj/item/ore/marble = list(REAGENT_ID_SILICON,REAGENT_ID_ALUMINIUM,REAGENT_ID_ALUMINIUM,REAGENT_ID_SODIUM,REAGENT_ID_CALCIUM), // Some nice variety here
	/obj/item/ore/uranium = list(REAGENT_ID_URANIUM),
	/obj/item/ore/diamond = list(REAGENT_ID_CARBON),
	/obj/item/ore/osmium = list(REAGENT_ID_PLATINUM), // should contain osmium
	/obj/item/ore/lead = list(REAGENT_ID_LEAD),
	/obj/item/ore/hydrogen = list(REAGENT_ID_HYDROGEN),
	/obj/item/ore/verdantium = list(REAGENT_ID_RADIUM,REAGENT_ID_PHORON,REAGENT_ID_NITROGEN,REAGENT_ID_PHOSPHORUS,REAGENT_ID_SODIUM), // Some fun stuff to be useful with
	/obj/item/ore/rutile = list(REAGENT_ID_TITANIUMDIOX,REAGENT_ID_OXYGEN),
	/obj/item/ore/copper = list(REAGENT_ID_COPPER),
	/obj/item/ore/tin = list(REAGENT_ID_TIN),
	/obj/item/ore/void_opal = list(REAGENT_ID_SILICON,REAGENT_ID_SILICON,REAGENT_ID_OXYGEN,REAGENT_ID_WATER),
	/obj/item/ore/painite = list(REAGENT_ID_CALCIUM,REAGENT_ID_ALUMINIUM,REAGENT_ID_OXYGEN,REAGENT_ID_OXYGEN),
	/obj/item/ore/quartz = list(REAGENT_ID_SILICON,REAGENT_ID_OXYGEN),
	/obj/item/ore/bauxite = list(REAGENT_ID_ALUMINIUM,REAGENT_ID_ALUMINIUM),
	))

// Don't need a new list for every grinder in the game
GLOBAL_LIST_INIT(reagent_sheets,list( // Recompressing reagents back into sheets
	REAGENT_ID_COPPER 			= MAT_COPPER,
	REAGENT_ID_TIN 				= MAT_TIN,
	REAGENT_ID_WOODPULP 		= MAT_CARDBOARD,
	REAGENT_ID_CARBON 			= MAT_GRAPHITE,
	REAGENT_ID_ALUMINIUM 		= MAT_ALUMINIUM,
	REAGENT_ID_TITANIUM 		= MAT_TITANIUM,
	REAGENT_ID_IRON 			= MAT_IRON,
	REAGENT_ID_LEAD				= MAT_LEAD,
	REAGENT_ID_URANIUM			= MAT_URANIUM,
	REAGENT_ID_GOLD 			= MAT_GOLD,
	REAGENT_ID_SILVER 			= MAT_SILVER,
	REAGENT_ID_PLATINUM			= MAT_PLATINUM,
	REAGENT_ID_SILICON 			= MAT_GLASS,
	// Mostly harmless
	REAGENT_ID_PROTEIN			= REFINERY_SINTERING_SMOKE,
	REAGENT_ID_TRIGLYCERIDE 	= REFINERY_SINTERING_SMOKE,
	REAGENT_ID_SODIUM	 		= REFINERY_SINTERING_SMOKE,
	REAGENT_ID_PHOSPHORUS 		= REFINERY_SINTERING_SMOKE,
	REAGENT_ID_ETHANOL 			= REFINERY_SINTERING_SMOKE,
	// Extremely stupid ones
	REAGENT_ID_OXYGEN 			= REFINERY_SINTERING_EXPLODE,
	REAGENT_ID_HYDROGEN 		= REFINERY_SINTERING_EXPLODE,
	REAGENT_ID_PHORON 			= REFINERY_SINTERING_EXPLODE,
	REAGENT_ID_SUPERMATTER 		= REFINERY_SINTERING_EXPLODE,
	// Nothing is funnier to me
	REAGENT_ID_SPIDEREGG 		= REFINERY_SINTERING_SPIDERS,
	))

GLOBAL_LIST_INIT(deepore_fracking_reagents,list( // Fracking results for fluid pump
	ORE_HEMATITE = list(REAGENT_ID_SILICATE,REAGENT_ID_IRON,REAGENT_ID_CARBON),
	ORE_URANIUM = list(REAGENT_ID_RADIUM,REAGENT_ID_RADIUM,REAGENT_ID_CALCIUM,REAGENT_ID_PHOSPHORUS), // Doesn't produce uranium due to low use in reagents, and emp reaction
	ORE_COPPER = list(REAGENT_ID_GOLD,REAGENT_ID_COPPER,REAGENT_ID_LEAD), // Commonly
	ORE_GOLD = list(REAGENT_ID_GOLD,REAGENT_ID_COPPER,REAGENT_ID_LEAD), // Found
	ORE_TIN = list(REAGENT_ID_GOLD,REAGENT_ID_COPPER,REAGENT_ID_LEAD), // Together
	ORE_SILVER = list(REAGENT_ID_SILVER,REAGENT_ID_LEAD,REAGENT_ID_COPPER), // lead loves this one too
	ORE_DIAMOND = list(REAGENT_ID_TITANIUMDIOX,REAGENT_ID_PHOSPHORUS,REAGENT_ID_SULFUR,REAGENT_ID_CARBON), // Ignius process
	ORE_PHORON = list(REAGENT_ID_PHORON,REAGENT_ID_RADIUM,REAGENT_ID_PHOSPHORUS,REAGENT_ID_SULFUR), // Ignius heavymetals?
	ORE_PLATINUM = list(REAGENT_ID_PLATINUM,REAGENT_ID_COPPER), // Don't have much to group it with
	ORE_MHYDROGEN = list(REAGENT_ID_SILICATE,REAGENT_ID_HYDROGEN),
	ORE_SAND = list(REAGENT_ID_SILICATE,REAGENT_ID_SILICON,REAGENT_ID_LITHIUM,REAGENT_ID_PHOSPHORUS,REAGENT_ID_CALCIUM,REAGENT_ID_SODIUMCHLORIDE,REAGENT_ID_CARBON), // Catch all sedimentry
	ORE_CARBON = list(REAGENT_ID_SILICATE,REAGENT_ID_CARBON,REAGENT_ID_SODIUMCHLORIDE), // Salty coal
	ORE_BAUXITE = list(REAGENT_ID_TITANIUMDIOX,REAGENT_ID_ALUMINIUM,REAGENT_ID_SODIUMCHLORIDE), // ore's general components and neighbours
	ORE_RUTILE = list(REAGENT_ID_TITANIUMDIOX,REAGENT_ID_SILICATE,REAGENT_ID_SILICON,REAGENT_ID_SODIUMCHLORIDE) // ore's general components and neighbours
	))

//List of the ammo types that can be used in game.
GLOBAL_LIST_INIT(global_ammo_types, list(
	/obj/item/ammo_casing/a357              = ".357",
	/obj/item/ammo_casing/a9mm		        = "9mm",
	/obj/item/ammo_casing/a45				= ".45",
	/obj/item/ammo_casing/a10mm             = "10mm",
	/obj/item/ammo_casing/a12g              = "12g",
	/obj/item/ammo_casing/a12g/pellet       = "12g",
	/obj/item/ammo_casing/a12g/beanbag      = "12g",
	/obj/item/ammo_casing/a12g/stunshell    = "12g",
	/obj/item/ammo_casing/a12g/flash        = "12g",
	/obj/item/ammo_casing/a762              = "7.62mm",
	/obj/item/ammo_casing/a545              = "5.45mm"
	))

//Rad collectors in the world (kept for fusion engine compatibility; under the
//LINDA migration the collectors are stub-only — see code/
//atmospherics/deleted_engine_stubs.dm).
GLOBAL_LIST_EMPTY(rad_collectors)
// algae/ten stack stub — used by hydroponics; algae generator was deleted with
// ZAS but the stack subtype is still referenced.

//NIF
GLOBAL_LIST_INIT(nif_look_messages, list(
			"flicks their eyes around",
			"looks at something unseen",
			"reads some invisible text",
			"seems to be daydreaming",
			"focuses elsewhere for a moment"))

GLOBAL_LIST(starting_legal_nifsoft)
GLOBAL_LIST(starting_illegal_nifsoft)

// By default they can be in any water turf.  Subtypes might restrict to deep/shallow etc
GLOBAL_LIST_INIT(suitable_fish_turf_types,  list(
	/turf/simulated/floor/beach/water,
	/turf/simulated/floor/beach/coastline,
	/turf/simulated/floor/holofloor/beach/water,
	/turf/simulated/floor/holofloor/beach/coastline,
	/turf/simulated/floor/water
))

GLOBAL_LIST_INIT(ventcrawl_machinery, list(
	/obj/machinery/atmospherics/unary/vent_pump,
	/obj/machinery/atmospherics/unary/vent_scrubber
	))

GLOBAL_LIST_BOILERPLATE(papers_dockingcode, /obj/item/paper/dockingcodes)

//Chamelion clothing was all stupid so it's done here instead.
//Jumpsuit
GLOBAL_LIST(chamelion_jumpsuit_choices)
//Hat
GLOBAL_LIST(chamelion_head_choices)
//Suit
GLOBAL_LIST(chamelion_suit_choices)
//Shoes
GLOBAL_LIST(chamelion_shoe_choices)
//Backpack
GLOBAL_LIST(chamelion_back_choices)
//Gloves
GLOBAL_LIST(chamelion_glove_choices)
//Mask
GLOBAL_LIST(chamelion_mask_choices)
//Belt
GLOBAL_LIST(chamelion_belt_choices)
//Accessory
GLOBAL_LIST(chamelion_accessory_choices)

GLOBAL_LIST_INIT(tail_layer_options, list("Lower layer" = TAIL_UPPER_LAYER_LOW , "Default layer" = TAIL_UPPER_LAYER , "Upper layer" = TAIL_UPPER_LAYER_HIGH ))

//Spritesheet stuff. Used by /obj/item/clothing/proc/refit_for_species(var/target_species)
#define SPECIES_HUMANOID_CAN_WEAR list(SPECIES_HUMAN, SPECIES_SKRELL, SPECIES_RAPALA, SPECIES_VASILISSAN, SPECIES_ALRAUNE, SPECIES_PROMETHEAN)
#define SPECIES_UNATHI_CAN_WEAR list(SPECIES_UNATHI, SPECIES_XENOHYBRID)
#define SPECIES_TAJARAN_CAN_WEAR list(SPECIES_TAJARAN, SPECIES_XENOCHIMERA)
#define SPECIES_VULPKANIN_CAN_WEAR list(SPECIES_VULPKANIN, SPECIES_ZORREN_HIGH, SPECIES_FENNEC)
#define SPECIES_SERGAL_CAN_WEAR list(SPECIES_SERGAL, SPECIES_NEVREAN)
#define SPECIES_TESHARI_CAN_WEAR list(SPECIES_TESHARI)
#define SPECIES_VOX_CAN_WEAR list(SPECIES_VOX)
#define SPECIES_ALL_BUT_TESHARI_CAN_WEAR list(SPECIES_HUMAN, SPECIES_SKRELL, SPECIES_RAPALA, SPECIES_VASILISSAN, SPECIES_ALRAUNE, SPECIES_PROMETHEAN, SPECIES_UNATHI, SPECIES_XENOHYBRID, SPECIES_TAJARAN, SPECIES_XENOCHIMERA, SPECIES_VULPKANIN, SPECIES_ZORREN_HIGH, SPECIES_FENNEC, SPECIES_SERGAL, SPECIES_NEVREAN, SPECIES_VOX, SPECIES_SHADEKIN)
#define SPECIES_ALL_BUT_TESHARI_AND_VOX_CAN_WEAR list(SPECIES_HUMAN, SPECIES_SKRELL, SPECIES_RAPALA, SPECIES_VASILISSAN, SPECIES_ALRAUNE, SPECIES_PROMETHEAN, SPECIES_UNATHI, SPECIES_XENOHYBRID, SPECIES_TAJARAN, SPECIES_XENOCHIMERA, SPECIES_VULPKANIN, SPECIES_ZORREN_HIGH, SPECIES_FENNEC, SPECIES_SERGAL, SPECIES_NEVREAN, SPECIES_SHADEKIN)
#define SPECIES_ALL_CAN_WEAR list(SPECIES_HUMAN, SPECIES_SKRELL, SPECIES_RAPALA, SPECIES_VASILISSAN, SPECIES_ALRAUNE, SPECIES_PROMETHEAN, SPECIES_UNATHI, SPECIES_XENOHYBRID, SPECIES_TAJARAN, SPECIES_XENOCHIMERA, SPECIES_VULPKANIN, SPECIES_ZORREN_HIGH, SPECIES_FENNEC, SPECIES_SERGAL, SPECIES_NEVREAN, SPECIES_TESHARI, SPECIES_VOX, SPECIES_SHADEKIN)


// === merged from global_lists_vr.dm during hard-fork de-suffix (manually verified: new global procs/lists, no base symbol collision) ===
/**
 * VOREStation global lists
*/

GLOBAL_LIST_EMPTY(hair_accesories_list) // Stores /datum/sprite_accessory/hair_accessory indexed by type
GLOBAL_LIST_EMPTY(negative_traits)	// Negative custom species traits, indexed by path
GLOBAL_LIST_EMPTY(neutral_traits)		// Neutral custom species traits, indexed by path
GLOBAL_LIST_EMPTY(positive_traits)	// Positive custom species traits, indexed by path
GLOBAL_LIST_EMPTY(everyone_traits_positive)	// Neutral traits available to all species, indexed by path
GLOBAL_LIST_EMPTY(everyone_traits_neutral)	// Neutral traits available to all species, indexed by path
GLOBAL_LIST_EMPTY(everyone_traits_negative)	// Neutral traits available to all species, indexed by path
GLOBAL_LIST_EMPTY(traits_costs)		// Just path = cost list, saves time in char setup
GLOBAL_LIST_EMPTY(all_traits)			// All of 'em at once (same instances)

GLOBAL_LIST_EMPTY(active_ghost_pods) //NYI - Used downstream
GLOBAL_LIST_EMPTY(latejoin_gatewaystation) //NYI - Used downstream
GLOBAL_LIST_EMPTY(latejoin_plainspath) //NYI - Used downstream
GLOBAL_LIST_EMPTY(latejoin_fueldepot) //NYI - Used downstream
GLOBAL_LIST_EMPTY(latejoin_tyrvillage) //NYI - Used downstream
GLOBAL_LIST_EMPTY(latejoin_thedark) //NYI - Used downstream
//Global vars for making the overmap_renamer subsystem.
//Collects all instances by reference of visitable overmap objects of /obj/effect/overmap/visitable like the debris field.
GLOBAL_LIST_EMPTY(visitable_overmap_object_instances)

GLOBAL_LIST_INIT(sensorpreflist, list("Off", "Binary", "Vitals", "Tracking", "No Preference"))

// Used by the ban panel to determine what departments are offmap departments. All these share an 'offmap roles' ban.
GLOBAL_LIST_INIT(offmap_departments, list(DEPARTMENT_TALON))

// Closets have magic appearances
GLOBAL_LIST_EMPTY(closet_appearances)

//stores numeric player size options indexed by name
GLOBAL_LIST_INIT(player_sizes_list, list(
		"Macro" 	= RESIZE_HUGE,
		"Big" 		= RESIZE_BIG,
		"Normal" 	= RESIZE_NORMAL,
		"Small" 	= RESIZE_SMALL,
		"Tiny" 		= RESIZE_TINY))

//stores vantag settings indexed by name
// start - expanding the vore hud list
GLOBAL_LIST_INIT(vantag_choices_list, list(
		VANTAG_NONE		=	"No Involvement",
		VANTAG_VORE		=	"Be Prey (Any)",
		VANTAG_VORE_YE	=	"Be Prey (Endo)",
		VANTAG_VORE_YD	=	"Be Prey (Digestion)",
		VANTAG_VORE_YA	=	"Be Prey (Absorption)",
		VANTAG_VORE_D	=	"Be Pred (Any)",
		VANTAG_VORE_DE	=	"Be Pred (Endo)",
		VANTAG_VORE_DD	=	"Be Pred (Digestion)",
		VANTAG_VORE_DA	=	"Be Pred (Absorption)",
		VANTAG_KIDNAP	=	"Be Kidnapped",
		VANTAG_KILL		=	"Be Killed"))
// end

//Blacklist to exclude items from object ingestion. Digestion blacklist located in digest_act_vr.dm
GLOBAL_LIST_INIT(item_vore_blacklist, list(
		/obj/item/hand_tele,
		/obj/item/card/id/gold/captain/spare,
		/obj/item/gun,
		/obj/item/pinpointer,
		/obj/item/clothing/shoes/magboots,
		/obj/item/areaeditor/blueprints,
		/obj/item/clothing/head/helmet/space,
		/obj/item/disk/nuclear))

//Classic Vore sounds
GLOBAL_LIST_INIT(classic_vore_sounds, list(
		"Gulp" = 'sound/vore/gulp.ogg',
		"Insert" = 'sound/vore/insert.ogg',
		"Insertion1" = 'sound/vore/insertion1.ogg',
		"Insertion2" = 'sound/vore/insertion2.ogg',
		"Insertion3" = 'sound/vore/insertion3.ogg',
		"Schlorp" = 'sound/vore/schlorp.ogg',
		"Squish1" = 'sound/vore/squish1.ogg',
		"Squish2" = 'sound/vore/squish2.ogg',
		"Squish3" = 'sound/vore/squish3.ogg',
		"Squish4" = 'sound/vore/squish4.ogg',
		"Rustle (cloth)" = 'sound/effects/rustle1.ogg',
		"Rustle 2 (cloth)"	= 'sound/effects/rustle2.ogg',
		"Rustle 3 (cloth)"	= 'sound/effects/rustle3.ogg',
		"Rustle 4 (cloth)"	= 'sound/effects/rustle4.ogg',
		"Rustle 5 (cloth)"	= 'sound/effects/rustle5.ogg',
		"Zipper" = 'sound/items/zip.ogg',
		"None" = null
		))

GLOBAL_LIST_INIT(classic_release_sounds, list(
		"Rustle (cloth)" = 'sound/effects/rustle1.ogg',
		"Rustle 2 (cloth)" = 'sound/effects/rustle2.ogg',
		"Rustle 3 (cloth)" = 'sound/effects/rustle3.ogg',
		"Rustle 4 (cloth)" = 'sound/effects/rustle4.ogg',
		"Rustle 5 (cloth)" = 'sound/effects/rustle5.ogg',
		"Zipper" = 'sound/items/zip.ogg',
		"Splatter" = 'sound/effects/splat.ogg',
		"None" = null
		))

//Poojy's Fancy Sounds
GLOBAL_LIST_INIT(fancy_vore_sounds, list(
		"Gulp" = 'sound/vore/sunesound/pred/swallow_01.ogg',
		"Swallow" = 'sound/vore/sunesound/pred/swallow_02.ogg',
		"Insertion1" = 'sound/vore/sunesound/pred/insertion_01.ogg',
		"Insertion2" = 'sound/vore/sunesound/pred/insertion_02.ogg',
		"Tauric Swallow" = 'sound/vore/sunesound/pred/taurswallow.ogg',
		"Stomach Move"		= 'sound/vore/sunesound/pred/stomachmove.ogg',
		"Schlorp" = 'sound/vore/sunesound/pred/schlorp.ogg',
		"Squish1" = 'sound/vore/sunesound/pred/squish_01.ogg',
		"Squish2" = 'sound/vore/sunesound/pred/squish_02.ogg',
		"Squish3" = 'sound/vore/sunesound/pred/squish_03.ogg',
		"Squish4" = 'sound/vore/sunesound/pred/squish_04.ogg',
		"Rustle (cloth)" = 'sound/effects/rustle1.ogg',
		"Rustle 2 (cloth)"	= 'sound/effects/rustle2.ogg',
		"Rustle 3 (cloth)"	= 'sound/effects/rustle3.ogg',
		"Rustle 4 (cloth)"	= 'sound/effects/rustle4.ogg',
		"Rustle 5 (cloth)"	= 'sound/effects/rustle5.ogg',
		"Zipper" = 'sound/items/zip.ogg',
		"None" = null
		))

GLOBAL_LIST_INIT(fancy_release_sounds, list(
		"Rustle (cloth)" = 'sound/effects/rustle1.ogg',
		"Rustle 2 (cloth)" = 'sound/effects/rustle2.ogg',
		"Rustle 3 (cloth)" = 'sound/effects/rustle3.ogg',
		"Rustle 4 (cloth)" = 'sound/effects/rustle4.ogg',
		"Rustle 5 (cloth)" = 'sound/effects/rustle5.ogg',
		"Zipper" = 'sound/items/zip.ogg',
		"Stomach Move" = 'sound/vore/sunesound/pred/stomachmove.ogg',
		"Pred Escape" = 'sound/vore/sunesound/pred/escape.ogg',
		"Splatter" = 'sound/effects/splat.ogg',
		"None" = null
		))

GLOBAL_LIST_INIT(global_vore_egg_types, list(
	"Unathi",
	"Tajara",
	"Akula",
	"Skrell",
	"Sergal",
	"Nevrean",
	"Human",
	"Slime",
	"Egg",
	"Xenochimera",
	"Xenomorph",
	"Chocolate",
	"Boney",
	"Slime Glob",
	"Chicken",
	"Synthetic",
	"Bluespace Floppy",
	"Bluespace Compressed File",
	"Bluespace CD",
	"Escape Pod",
	"Cooking Error",
	"Web Cocoon",
	"Honeycomb",
	"Bug Cocoon",
	"Rock",
	"Yellow",
	"Blue",
	"Green",
	"Orange",
	"Purple",
	"Red",
	"Rainbow",
	"Spotted Pink"
	))

// Global associated list of common items people might prefer to be item TF'd into
GLOBAL_LIST_INIT(item_tf_options, list(
	// Accessories
	"Accessory - Ring"							= /obj/item/clothing/accessory/ring,
	"Accessory - Sweater"						= /obj/item/clothing/accessory/sweater,
	"Accessory - Sweater (keyhole)"				= /obj/item/clothing/accessory/sweater/keyhole,
	// Under slot items
	"Top - Bunny suit"							= /obj/item/clothing/under/bunnysuit,
	"Top - Bunny suit (maid)"					= /obj/item/clothing/under/bunnysuit_maid,
	"Top - Bunny suit (maid, top-only)"			= /obj/item/clothing/under/reverse_bunnytop_maid,
	"Top - Bunny suit (reverse)"				= /obj/item/clothing/under/reverse_bunnysuit,
	"Top - Bunny suit (reverse, maid)"			= /obj/item/clothing/under/reverse_bunnysuit_maid,
	"Top - Bunny suit (reverse, top-only)"		= /obj/item/clothing/under/reverse_bunnytop,
	"Top - Maid outfit (costume)"				= /obj/item/clothing/under/dress/maid,
	"Top - Maid outfit (uniform)"				= /obj/item/clothing/under/dress/maid/janitor,
	"Top - Swimsuit (black)"					= /obj/item/clothing/under/swimsuit/black,
	"Top - Swimsuit (blue)"						= /obj/item/clothing/under/swimsuit/blue,
	"Top - Swimsuit (cow print)"				= /obj/item/clothing/under/swimsuit/cowbikini,
	"Top - Swimsuit (earthen)"					= /obj/item/clothing/under/swimsuit/earth,
	"Top - Swimsuit (green)"					= /obj/item/clothing/under/swimsuit/green,
	"Top - Swimsuit (high class)"				= /obj/item/clothing/under/swimsuit/highclass,
	"Top - Swimsuit (purple)"					= /obj/item/clothing/under/swimsuit/purple,
	"Top - Swimsuit (red)"						= /obj/item/clothing/under/swimsuit/red,
	"Top - Swimsuit (revealing, pink)"			= /obj/item/clothing/under/swimsuit/stripper,
	"Top - Swimsuit (risque)"					= /obj/item/clothing/under/swimsuit/risque,
	"Top - Swimsuit (streamlined)"				= /obj/item/clothing/under/swimsuit/streamlined,
	"Top - Swimsuit (striped)"					= /obj/item/clothing/under/swimsuit/striped,
	"Top - Swimsuit (white)"					= /obj/item/clothing/under/swimsuit/white,
	// Foot slot items
	"Footwear - Flip-flops"						= /obj/item/clothing/shoes/flipflop,
	"Footwear - Footwraps"						= /obj/item/clothing/shoes/footwraps,
	"Footwear - High heels"						= /obj/item/clothing/shoes/heels,
	"Footwear - Jackboots"						= /obj/item/clothing/shoes/boots/jackboots,
	"Footwear - Jackboots (toe-less)"			= /obj/item/clothing/shoes/boots/jackboots/toeless,
	"Footwear - Shoes (black)"					= /obj/item/clothing/shoes/black,
	"Footwear - Workboots"						= /obj/item/clothing/shoes/boots/workboots,
	"Footwear - Workboots (toe-less)"			= /obj/item/clothing/shoes/boots/workboots/toeless,
	// Hand slot items
	"Gloves - Evening"							= /obj/item/clothing/gloves/evening,
	"Gloves - Black"							= /obj/item/clothing/gloves/black,
	// Suit slot items
	"Overwear - Kimono (blue)"					= /obj/item/clothing/suit/kimono/blue,
	"Overwear - Kimono (earth)"					= /obj/item/clothing/suit/kimono/blue,
	"Overwear - Kimono (green)"					= /obj/item/clothing/suit/kimono/green,
	"Overwear - Kimono (orange)"				= /obj/item/clothing/suit/kimono/orange,
	"Overwear - Kimono (pink)"					= /obj/item/clothing/suit/kimono/pink,
	"Overwear - Kimono (purple)"				= /obj/item/clothing/suit/kimono/purple,
	"Overwear - Kimono (red)"					= /obj/item/clothing/suit/kimono/red,
	"Overwear - Kimono (violet)"				= /obj/item/clothing/suit/kimono/violet,
	"Overwear - Kimono (white, traditional)"	= /obj/item/clothing/suit/kimono,
	"Overwear - T-shirt (oversized)"			= /obj/item/clothing/suit/oversize,
	// Misc. items
	"Item - Bar stool"							= /obj/item/stool/padded,
	"Item - Inflatable Duck"					= /obj/item/inflatable_duck,
	"Item - Plushie (carp)"						= /obj/item/toy/plushie/carp,
	"Item - Plushie (cat, black)"				= /obj/item/toy/plushie/black_cat,
	"Item - Plushie (cat, calico)"				= /obj/item/toy/plushie/kitten,
	"Item - Plushie (cat, grey)"				= /obj/item/toy/plushie/grey_cat,
	"Item - Plushie (cat, orange)"				= /obj/item/toy/plushie/orange_cat,
	"Item - Plushie (cat, tabby)"				= /obj/item/toy/plushie/tabby_cat,
	"Item - Plushie (cat, tuxedo)"				= /obj/item/toy/plushie/tuxedo_cat,
	"Item - Plushie (cat, white)"				= /obj/item/toy/plushie/white_cat,
	"Item - Plushie (corgi)"					= /obj/item/toy/plushie/corgi,
	"Item - Plushie (corgi, girly)"				= /obj/item/toy/plushie/girly_corgi,
	"Item - Plushie (deer)"						= /obj/item/toy/plushie/deer,
	"Item - Plushie (fox, black)"				= /obj/item/toy/plushie/black_fox,
	"Item - Plushie (fox, blue)"				= /obj/item/toy/plushie/blue_fox,
	"Item - Plushie (fox, coffee)"				= /obj/item/toy/plushie/coffee_fox,
	"Item - Plushie (fox, crimson)"				= /obj/item/toy/plushie/crimson_fox,
	"Item - Plushie (fox, marble)"				= /obj/item/toy/plushie/marble_fox,
	"Item - Plushie (fox, orange)"				= /obj/item/toy/plushie/orange_fox,
	"Item - Plushie (fox, pink)"				= /obj/item/toy/plushie/pink_fox,
	"Item - Plushie (fox, purple)"				= /obj/item/toy/plushie/purple_fox,
	"Item - Plushie (fox, red)"					= /obj/item/toy/plushie/red_fox,
	"Item - Plushie (fumo)"						= /obj/item/toy/plushie/fumo,
	"Item - Plushie (lizard)"					= /obj/item/toy/plushie/lizard,
	"Item - Plushie (lizard, kobold)"			= /obj/item/toy/plushie/lizardplushie/kobold,
	"Item - Plushie (moth)"						= /obj/item/toy/plushie/moth,
	"Item - Plushie (mouse)"					= /obj/item/toy/plushie/mouse,
	"Item - Plushie (shark)"					= /obj/item/toy/plushie/shark,
	"Item - Plushie (slime)"					= /obj/item/toy/plushie/slimeplushie,
	"Item - Plushie (snake)"					= /obj/item/toy/plushie/snakeplushie,
	"Item - Plushie (spider)"					= /obj/item/toy/plushie/spider,
	"Item - Plushie (vox)"						= /obj/item/toy/plushie/vox,
	"Item - Towel"								= /obj/item/towel
	))

GLOBAL_LIST_INIT(tf_vore_egg_types, list(
	"Unathi" 		= /obj/item/storage/vore_egg/unathi,
	"Tajara" 		= /obj/item/storage/vore_egg/tajaran,
	"Akula" 		= /obj/item/storage/vore_egg/shark,
	"Skrell" 		= /obj/item/storage/vore_egg/skrell,
	"Sergal"		= /obj/item/storage/vore_egg/sergal,
	"Nevrean"		= /obj/item/storage/vore_egg/nevrean,
	"Human"			= /obj/item/storage/vore_egg/human,
	"Slime"			= /obj/item/storage/vore_egg/slime,
	"Egg"			= /obj/item/storage/vore_egg,
	"Xenochimera"	= /obj/item/storage/vore_egg/scree,
	"Xenomorph"		= /obj/item/storage/vore_egg/xenomorph,
	"Chocolate"		= /obj/item/storage/vore_egg/chocolate,
	"Boney"			= /obj/item/storage/vore_egg/owlpellet,
	"Slime Glob"	= /obj/item/storage/vore_egg/slimeglob,
	"Chicken"		= /obj/item/storage/vore_egg/chicken,
	"Synthetic"		= /obj/item/storage/vore_egg/synthetic,
	"Bluespace Floppy"	= /obj/item/storage/vore_egg/floppy,
	"Bluespace Compressed File"	= /obj/item/storage/vore_egg/file,
	"Bluespace CD"	= /obj/item/storage/vore_egg/cd,
	"Escape Pod"	= /obj/item/storage/vore_egg/escapepod,
	"Cooking Error"	= /obj/item/storage/vore_egg/badrecipe,
	"Web Cocoon"	= /obj/item/storage/vore_egg/cocoon,
	"Honeycomb"	= /obj/item/storage/vore_egg/honeycomb,
	"Bug Cocoon"	= /obj/item/storage/vore_egg/bugcocoon,
	"Rock"			= /obj/item/storage/vore_egg/rock,
	"Yellow"		= /obj/item/storage/vore_egg/yellow,
	"Blue"			= /obj/item/storage/vore_egg/blue,
	"Green"			= /obj/item/storage/vore_egg/green,
	"Orange"		= /obj/item/storage/vore_egg/orange,
	"Purple"		= /obj/item/storage/vore_egg/purple,
	"Red"			= /obj/item/storage/vore_egg/red,
	"Rainbow"		= /obj/item/storage/vore_egg/rainbow,
	"Spotted Pink"	= /obj/item/storage/vore_egg/pinkspots))

GLOBAL_LIST_INIT(edible_trash, list(/obj/item/broken_device,
				/obj/item/clothing/accessory/collar,
				/obj/item/communicator,
				/obj/item/clothing/mask,
				/obj/item/clothing/glasses,
				/obj/item/clothing/gloves,
				/obj/item/clothing/head,
				/obj/item/clothing/shoes,
				/obj/item/aicard,
				/obj/item/flashlight,
				/obj/item/mmi/digital/posibrain,
				/obj/item/paicard,
				/obj/item/pda,
				/obj/item/radio/headset,
				/obj/item/starcaster_news,
				/obj/item/inflatable/torn,
				/obj/item/organ,
				/obj/item/stack/material/cardboard,
				/obj/item/toy,
				/obj/item/trash,
				/obj/item/digestion_remains,
				/obj/item/bananapeel,
				/obj/item/book,
				/obj/item/bone,
				/obj/item/broken_bottle,
				/obj/item/card/emag_broken,
				/obj/item/trash/cigbutt,
				/obj/item/circuitboard/broken,
				/obj/item/clipboard,
				/obj/item/corncob,
				/obj/item/dice,
				/obj/item/flame,
				/obj/item/light,
				/obj/item/lipstick,
				/obj/item/material/shard,
				/obj/item/newspaper,
				/obj/item/paper,
				/obj/item/paperplane,
				/obj/item/pen,
				/obj/item/photo,
				/obj/item/reagent_containers/food,
				/obj/item/reagent_containers/glass/rag,
				/obj/item/soap,
				/obj/item/spacecash,
				/obj/item/storage/box/matches,
				/obj/item/storage/box/wings,
				/obj/item/storage/fancy/candle_box,
				/obj/item/storage/fancy/cigarettes,
				/obj/item/storage/fancy/crayons,
				/obj/item/storage/fancy/egg_box,
				/obj/item/storage/wallet,
				/obj/item/storage/vore_egg,
				/obj/item/bikehorn/tinytether,
				/obj/item/entrepreneur,
				/obj/item/capture_crystal,
				/obj/item/material/kitchen,
				/obj/item/storage/mre,
				/obj/item/storage/mrebag,
				/obj/item/storage/fancy/crackers,
				/obj/item/storage/fancy/heartbox,
				/obj/item/pizzavoucher,
				/obj/item/pizzabox,
				/obj/item/toy,
				/obj/item/seeds,
				/obj/item/clothing/accessory/choker,
				/obj/item/clothing/accessory/medal,
				/obj/item/clothing/accessory/tie,
				/obj/item/clothing/accessory/scarf,
				/obj/item/clothing/accessory/bracelet,
				/obj/item/clothing/accessory/locket,
				/obj/item/storage/bible,
				/obj/item/bikehorn,
				/obj/item/inflatable/door/torn,
				/obj/item/towel,
				/obj/item/folder,
				/obj/item/clipboard,
				/obj/item/coin,
				/obj/item/clothing/ears,
				/obj/item/roulette_ball,
				/obj/item/pizzabox,
				/obj/item/card/id
				))

GLOBAL_LIST_INIT(contamination_flavors, list(
				"Generic" = GLOB.contamination_flavors_generic,
				"Acrid" = GLOB.contamination_flavors_acrid,
				"Dirty" = GLOB.contamination_flavors_dirty,
				"Musky" = GLOB.contamination_flavors_musky,
				"Smelly" = GLOB.contamination_flavors_smelly,
				"Slimy" = GLOB.contamination_flavors_slimy,
				"Wet" = GLOB.contamination_flavors_wet))

GLOBAL_LIST_INIT(contamination_flavors_generic, list("acrid",
				"bedraggled",
				"begrimed",
				"churned",
				"contaminated",
				"cruddy",
				"damp",
				"digested",
				"dirty",
				"disgusting",
				"drenched",
				"drippy",
				"filthy",
				"foul",
				"funky",
				"gloppy",
				"gooey",
				"grimy",
				"gross",
				"gruesome",
				"gunky",
				"icky",
				"juicy",
				"messy",
				"mucky",
				"mushy",
				"nasty",
				"noxious",
				"oozing",
				"pungent",
				"putrescent",
				"putrid",
				"repulsive",
				"saucy",
				"slimy",
				"sloppy",
				"sloshed",
				"sludgy",
				"smeary",
				"smelly",
				"smudgy",
				"smutty",
				"soaked",
				"soggy",
				"soiled",
				"sopping",
				"squashy",
				"squishy",
				"stained",
				"sticky",
				"stinky",
				"tainted",
				"tarnished",
				"unclean",
				"unsanitary",
				"unsavory",
				"yucky"))

GLOBAL_LIST_INIT(contamination_flavors_wet, list("damp",
				"drenched",
				"drippy",
				"gloppy",
				"gooey",
				"juicy",
				"oozing",
				"slimy",
				"slobbery",
				"sloppy",
				"sloshed",
				"sloughy",
				"sludgy",
				"slushy",
				"soaked",
				"soggy",
				"sopping",
				"squashy",
				"squishy",
				"sticky"))

GLOBAL_LIST_INIT(contamination_flavors_smelly, list("disgusting",
				"filthy",
				"foul",
				"funky",
				"gross",
				"icky",
				"malodorous",
				"nasty",
				"niffy",
				"noxious",
				"pungent",
				"putrescent",
				"putrid",
				"rancid",
				"reeking",
				"repulsive",
				"smelly",
				"stenchy",
				"stinky",
				"unsavory",
				"whiffy",
				"yucky"))

GLOBAL_LIST_INIT(contamination_flavors_acrid, list("acrid",
				"caustic",
				"churned",
				"chymous",
				"digested",
				"discolored",
				"disgusting",
				"drippy",
				"foul",
				"gloppy",
				"gooey",
				"grimy",
				"gross",
				"gruesome",
				"icky",
				"mucky",
				"mushy",
				"nasty",
				"noxious",
				"oozing",
				"pungent",
				"putrescent",
				"putrid",
				"repulsive",
				"saucy",
				"slimy",
				"sloppy",
				"sloshed",
				"sludgy",
				"slushy",
				"smelly",
				"smudgy",
				"soupy",
				"squashy",
				"squishy",
				"stained",
				"sticky",
				"tainted",
				"unsavory",
				"yucky"))

GLOBAL_LIST_INIT(contamination_flavors_dirty, list("bedraggled",
				"begrimed",
				"besmirched",
				"blemished",
				"contaminated",
				"cruddy",
				"dirty",
				"discolored",
				"filthy",
				"gloppy",
				"gooey",
				"grimy",
				"gross",
				"grubby",
				"gruesome",
				"gunky",
				"messy",
				"mucky",
				"mushy",
				"nasty",
				"saucy",
				"slimy",
				"sloppy",
				"sludgy",
				"smeary",
				"smudgy",
				"smutty",
				"soiled",
				"stained",
				"sticky",
				"tainted",
				"tarnished",
				"unclean",
				"unsanitary",
				"unsavory"))

GLOBAL_LIST_INIT(contamination_flavors_musky, list("drenched",
				"drippy",
				"funky",
				"gooey",
				"juicy",
				"messy",
				"musky",
				"nasty",
				"raunchy",
				"saucy",
				"slimy",
				"sloppy",
				"slushy",
				"smeary",
				"smelly",
				"smutty",
				"soggy",
				"squashy",
				"squishy",
				"sticky",
				"tainted"))

GLOBAL_LIST_INIT(contamination_flavors_slimy, list("slimy",
				"sloppy",
				"drippy",
				"glistening",
				"dripping",
				"gunky",
				"slimed",
				"mucky",
				"viscous",
				"dank",
				"glutinous",
				"syrupy",
				"slippery",
				"gelatinous"
				))

GLOBAL_LIST_INIT(contamination_colors, list("green",
				"white",
				"black",
				"grey",
				"yellow",
				"red",
				"blue",
				"orange",
				"purple",
				"lime",
				"brown",
				"darkred",
				"cyan",
				"beige",
				"pink"
				))

//For the mechanic of leaving remains. Ones listed below are basically ones that got no bones or leave no trace after death.
GLOBAL_LIST_INIT(remainless_species, list(SPECIES_PROMETHEAN,
				SPECIES_DIONA,
				SPECIES_ALRAUNE,
				SPECIES_PROTEAN,
				/*
				SPECIES_MONKEY, // Exclude all monkey subtypes, to prevent abuse of it. They aren't, // How about let preds have skeletons, people can do so much worse than this
				SPECIES_MONKEY_TAJ,				//set to have remains anyway, but making double sure,
				SPECIES_MONKEY_SKRELL,
				SPECIES_MONKEY_UNATHI,
				SPECIES_MONKEY_AKULA,
				SPECIES_MONKEY_NEVREAN,
				SPECIES_MONKEY_SERGAL,
				SPECIES_MONKEY_VULPKANIN,
				*/
				SPECIES_XENO,					//Same for xenos,
				SPECIES_XENO_DRONE,
				SPECIES_XENO_HUNTER,
				SPECIES_XENO_SENTINEL,
				SPECIES_XENO_QUEEN,
				SPECIES_SHADOW,
				SPECIES_GOLEM,					//Some special species that may or may not be ever used in event too,
				SPECIES_SHADEKIN))			//Shadefluffers just poof away

GLOBAL_LIST_INIT(alt_titles_with_icons, list(
				JOB_ALT_VIROLOGIST,
				JOB_ALT_APPRENTICE_ENGINEER,
				JOB_ALT_MEDICAL_INTERN,
				JOB_ALT_RESEARCH_INTERN,
				JOB_ALT_SECURITY_CADET,
				JOB_ALT_JR_CARGO_TECH,
				JOB_ALT_JR_EXPLORER,
				JOB_ALT_SERVER,
				JOB_ALT_ELECTRICIAN,
				JOB_ALT_FIREFIGHTER,
				JOB_ALT_BARISTA))

GLOBAL_LIST_EMPTY(existing_solargrubs)

/hook/startup/proc/init_vore_datum_ref_lists()
	var/paths

	// Custom Hair Accessories
	paths = subtypesof(/datum/sprite_accessory/hair_accessory)
	for(var/path in paths)
		var/datum/sprite_accessory/hair_accessory/instance = new path()
		GLOB.hair_accesories_list[path] = instance

	// Custom species traits
	paths = typesof(/datum/trait) - /datum/trait - /datum/trait/negative - /datum/trait/neutral - /datum/trait/positive
	for(var/path in paths)
		var/datum/trait/instance = new path()
		if(!instance.name)
			continue //A prototype or something
		var/cost = instance.cost
		GLOB.traits_costs[path] = cost
		GLOB.all_traits[path] = instance

	// Traitgenes Initilize trait genes
	setupgenetics(GLOB.all_traits)

	// Shakey shakey shake
	sortTim(GLOB.all_traits, GLOBAL_PROC_REF(cmp_trait_datums_name), associative = TRUE)

	// Split 'em up
	for(var/traitpath in GLOB.all_traits)
		var/datum/trait/T = GLOB.all_traits[traitpath]
		var/category = T.category
		if(!T.hidden) // Traitgenes forbid hidden traits from showing, done to hide genetics only traits
			switch(category)
				if(-INFINITY to -0.1)
					GLOB.negative_traits[traitpath] = T
					if(!(T.custom_only))
						GLOB.everyone_traits_negative[traitpath] = T
				if(0)
					GLOB.neutral_traits[traitpath] = T
					if(!(T.custom_only))
						GLOB.everyone_traits_neutral[traitpath] = T
				if(0.1 to INFINITY)
					GLOB.positive_traits[traitpath] = T
					if(!(T.custom_only))
						GLOB.everyone_traits_positive[traitpath] = T


	// Weaver recipe stuff
	paths = subtypesof(/datum/weaver_recipe/structure)
	for(var/path in paths)
		var/datum/weaver_recipe/instance = new path()
		if(!instance.title)
			continue //A prototype or something
		GLOB.weavable_structures[instance.title] = instance

	paths = subtypesof(/datum/weaver_recipe/item)
	for(var/path in paths)
		var/datum/weaver_recipe/instance = new path()
		if(!instance.title)
			continue //A prototype or something
		GLOB.weavable_items[instance.title] = instance

	paths = subtypesof(/datum/weaver_recipe)
	for(var/path in paths)
		var/datum/weaver_recipe/instance = new path()
		if(!instance.title)
			continue //A prototype or something
		GLOB.all_weavable[instance.title] = instance

	return 1 // Hooks must return 1

GLOBAL_LIST_EMPTY(weavable_structures)
GLOBAL_LIST_EMPTY(weavable_items)
GLOBAL_LIST_EMPTY(all_weavable)


GLOBAL_LIST_INIT(xenobio_metal_materials_normal, list(
										/obj/item/stack/material/steel = 20,
										/obj/item/stack/material/glass = 15,
										/obj/item/stack/material/plastic = 12,
										/obj/item/stack/material/wood = 12,
										/obj/item/stack/material/cardboard = 6,
										/obj/item/stack/material/sandstone = 5,
										/obj/item/stack/material/log = 5,
										/obj/item/stack/material/lead = 5,
										/obj/item/stack/material/iron = 5,
										/obj/item/stack/material/graphite = 5,
										/obj/item/stack/material/copper = 4,
										/obj/item/stack/material/tin = 4,
										/obj/item/stack/material/bronze = 4,
										/obj/item/stack/material/aluminium = 4))

GLOBAL_LIST_INIT(xenobio_metal_materials_adv, list(
										/obj/item/stack/material/glass/reinforced = 15,
										/obj/item/stack/material/marble = 10,
										/obj/item/stack/material/plasteel = 10,
										/obj/item/stack/material/glass/phoronglass = 10,
										/obj/item/stack/material/wood/sif = 5,
										/obj/item/stack/material/wood/hard = 5,
										/obj/item/stack/material/log/sif = 5,
										/obj/item/stack/material/log/hard = 5,
										/obj/item/stack/material/glass/phoronrglass = 5,
										/obj/item/stack/material/glass/titanium = 3,
										/obj/item/stack/material/glass/plastitanium = 3,
										/obj/item/stack/material/durasteel = 2,
										/obj/item/stack/material/painite = 1,
										/obj/item/stack/material/void_opal = 1,
										/obj/item/stack/material/quartz = 1))

GLOBAL_LIST_INIT(xenobio_metal_materials_weird, list(
										/obj/item/stack/material/cloth = 10,
										/obj/item/stack/material/leather = 5,
										/obj/item/stack/material/fiber = 5,
										/obj/item/stack/material/fur/wool = 7,
										/obj/item/stack/material/snow = 3,
										/obj/item/stack/material/snowbrick = 3,
										/obj/item/stack/material/flint = 3,
										/obj/item/stack/material/stick = 3,
										/obj/item/stack/material/chitin = 1))

GLOBAL_LIST_INIT(xenobio_silver_materials_basic, list(
										/obj/item/stack/material/silver = 10,
										/obj/item/stack/material/uranium = 8,
										/obj/item/stack/material/gold = 6,
										/obj/item/stack/material/titanium = 4,
										/obj/item/stack/material/phoron = 1))

GLOBAL_LIST_INIT(xenobio_silver_materials_adv, list(
										/obj/item/stack/material/deuterium = 5,
										/obj/item/stack/material/tritium = 5,
										/obj/item/stack/material/osmium = 5,
										/obj/item/stack/material/mhydrogen = 3,
										/obj/item/stack/material/diamond = 2,
										/obj/item/stack/material/verdantium = 1))

GLOBAL_LIST_INIT(xenobio_silver_materials_special, list(
										/obj/item/stack/material/valhollide = 1,
										/obj/item/stack/material/morphium = 1,
										/obj/item/stack/material/supermatter = 1))

GLOBAL_LIST_INIT(xenobio_gold_mobs_hostile, list(
										/mob/living/simple_mob/vore/alienanimals/space_jellyfish,
										/mob/living/simple_mob/vore/alienanimals/skeleton,
										/mob/living/simple_mob/vore/alienanimals/space_ghost,
										/mob/living/simple_mob/vore/alienanimals/startreader,
										/mob/living/simple_mob/animal/passive/mouse/operative,
										/mob/living/simple_mob/animal/giant_spider,
										/mob/living/simple_mob/animal/giant_spider/frost,
										/mob/living/simple_mob/animal/giant_spider/electric,
										/mob/living/simple_mob/animal/giant_spider/hunter,
										/mob/living/simple_mob/animal/giant_spider/lurker,
										/mob/living/simple_mob/animal/giant_spider/pepper,
										/mob/living/simple_mob/animal/giant_spider/thermic,
										/mob/living/simple_mob/animal/giant_spider/tunneler,
										/mob/living/simple_mob/animal/giant_spider/webslinger,
										/mob/living/simple_mob/animal/giant_spider/phorogenic,
										/mob/living/simple_mob/animal/giant_spider/carrier,
										/mob/living/simple_mob/animal/giant_spider/ion,
										/mob/living/simple_mob/animal/sif/diyaab,
										/mob/living/simple_mob/animal/sif/duck,
										/mob/living/simple_mob/animal/sif/frostfly,
										/mob/living/simple_mob/animal/sif/glitterfly,
										/mob/living/simple_mob/animal/sif/hooligan_crab,
										/mob/living/simple_mob/animal/sif/kururak,
										/mob/living/simple_mob/animal/sif/leech,
										/mob/living/simple_mob/animal/sif/tymisian,
										/mob/living/simple_mob/animal/sif/sakimm,
										/mob/living/simple_mob/animal/sif/savik,
										/mob/living/simple_mob/animal/sif/shantak,
										/mob/living/simple_mob/animal/sif/siffet,
										/mob/living/simple_mob/animal/space/alien,
										/mob/living/simple_mob/animal/space/alien/drone,
										/mob/living/simple_mob/animal/space/alien/sentinel,
										/mob/living/simple_mob/animal/space/alien/sentinel/praetorian,
										/mob/living/simple_mob/animal/space/alien/queen,
										/mob/living/simple_mob/animal/space/alien/queen/empress,
										/mob/living/simple_mob/animal/space/alien/queen/empress/mother,
										/mob/living/simple_mob/animal/space/bats,
										/mob/living/simple_mob/animal/space/bear,
										/mob/living/simple_mob/animal/space/carp,
										/mob/living/simple_mob/animal/space/carp/large,
										/mob/living/simple_mob/animal/space/carp/large/huge,
										/mob/living/simple_mob/animal/space/goose,
										/mob/living/simple_mob/creature,
										/mob/living/simple_mob/faithless,
										/mob/living/simple_mob/tomato,
										/mob/living/simple_mob/animal/space/tree,
										/mob/living/simple_mob/vore/aggressive/corrupthound,
										/mob/living/simple_mob/vore/aggressive/corrupthound/prettyboi,
										/mob/living/simple_mob/vore/aggressive/deathclaw,
										/mob/living/simple_mob/vore/aggressive/dino,
										/mob/living/simple_mob/vore/aggressive/dragon,
										/mob/living/simple_mob/vore/aggressive/frog,
										/mob/living/simple_mob/vore/otie,
										/mob/living/simple_mob/vore/otie/red,
										/mob/living/simple_mob/vore/aggressive/panther,
										/mob/living/simple_mob/vore/aggressive/rat,
										/mob/living/simple_mob/vore/aggressive/giant_snake,
										/mob/living/simple_mob/vore/sect_drone,
										/mob/living/simple_mob/vore/sect_queen,
										/mob/living/simple_mob/vore/weretiger,
										/mob/living/simple_mob/vore/wolf,
										/mob/living/simple_mob/vore/xeno_defanged))

GLOBAL_LIST_INIT(xenobio_gold_mobs_bosses, list(
										/mob/living/simple_mob/animal/giant_spider/broodmother,
										/mob/living/simple_mob/vore/leopardmander,
										/mob/living/simple_mob/vore/leopardmander/blue,
										/mob/living/simple_mob/vore/leopardmander/exotic,
										/mob/living/simple_mob/vore/greatwolf,
										/mob/living/simple_mob/vore/greatwolf/black,
										/mob/living/simple_mob/vore/greatwolf/grey,
										/mob/living/simple_mob/vore/bigdragon))

GLOBAL_LIST_INIT(xenobio_gold_mobs_safe, list(
										/mob/living/simple_mob/vore/alienanimals/dustjumper,
										/mob/living/simple_mob/vore/alienanimals/teppi,
										/mob/living/simple_mob/animal/passive/chicken,
										/mob/living/simple_mob/animal/passive/cow,
										/mob/living/simple_mob/animal/goat,
										/mob/living/simple_mob/animal/passive/crab,
										/mob/living/simple_mob/animal/passive/mouse/jerboa,
										/mob/living/simple_mob/animal/passive/lizard,
										/mob/living/simple_mob/animal/passive/lizard/large,
										/mob/living/simple_mob/animal/passive/yithian,
										/mob/living/simple_mob/animal/passive/tindalos,
										/mob/living/simple_mob/animal/passive/mouse,
										/mob/living/simple_mob/animal/passive/penguin,
										/mob/living/simple_mob/animal/passive/opossum,
										/mob/living/simple_mob/animal/passive/cat,
										/mob/living/simple_mob/animal/passive/dog/corgi,
										/mob/living/simple_mob/animal/passive/dog/void_puppy,
										/mob/living/simple_mob/animal/passive/dog/bullterrier,
										/mob/living/simple_mob/animal/passive/dog/tamaskan,
										/mob/living/simple_mob/animal/passive/dog/brittany,
										/mob/living/simple_mob/animal/passive/fox,
										/mob/living/simple_mob/animal/passive/fox/syndicate,
										/mob/living/simple_mob/animal/passive/hare,
										/mob/living/simple_mob/animal/passive/pillbug,
										/mob/living/simple_mob/animal/passive/gaslamp,
										/mob/living/simple_mob/animal/passive/snake,
										/mob/living/simple_mob/animal/passive/snake/red,
										/mob/living/simple_mob/animal/passive/snake/python,
										/mob/living/simple_mob/vore/bee,
										/mob/living/simple_mob/vore/fennec,
										/mob/living/simple_mob/vore/fennix,
										/mob/living/simple_mob/vore/seagull,
										/mob/living/simple_mob/vore/hippo,
										/mob/living/simple_mob/vore/horse,
										/mob/living/simple_mob/vore/jelly,
										/mob/living/simple_mob/vore/oregrub,
										/mob/living/simple_mob/vore/oregrub/lava,
										/mob/living/simple_mob/vore/rabbit,
										/mob/living/simple_mob/vore/redpanda,
										/mob/living/simple_mob/vore/sheep,
										/mob/living/simple_mob/vore/squirrel,
										/mob/living/simple_mob/vore/solargrub))

GLOBAL_LIST_INIT(xenobio_gold_mobs_birds, list(/mob/living/simple_mob/animal/passive/bird/black_bird,
										/mob/living/simple_mob/animal/passive/bird/azure_tit,
										/mob/living/simple_mob/animal/passive/bird/european_robin,
										/mob/living/simple_mob/animal/passive/bird/goldcrest,
										/mob/living/simple_mob/animal/passive/bird/ringneck_dove,
										/mob/living/simple_mob/animal/passive/bird/parrot,
										/mob/living/simple_mob/animal/passive/bird/parrot/kea,
										/mob/living/simple_mob/animal/passive/bird/parrot/eclectus,
										/mob/living/simple_mob/animal/passive/bird/parrot/grey_parrot,
										/mob/living/simple_mob/animal/passive/bird/parrot/black_headed_caique,
										/mob/living/simple_mob/animal/passive/bird/parrot/white_caique,
										/mob/living/simple_mob/animal/passive/bird/parrot/budgerigar,
										/mob/living/simple_mob/animal/passive/bird/parrot/budgerigar/blue,
										/mob/living/simple_mob/animal/passive/bird/parrot/budgerigar/bluegreen,
										/mob/living/simple_mob/animal/passive/bird/parrot/cockatiel,
										/mob/living/simple_mob/animal/passive/bird/parrot/cockatiel/white,
										/mob/living/simple_mob/animal/passive/bird/parrot/cockatiel/yellowish,
										/mob/living/simple_mob/animal/passive/bird/parrot/cockatiel/grey,
										/mob/living/simple_mob/animal/passive/bird/parrot/sulphur_cockatoo,
										/mob/living/simple_mob/animal/passive/bird/parrot/white_cockatoo,
										/mob/living/simple_mob/animal/passive/bird/parrot/pink_cockatoo))			//There's too dang many

GLOBAL_LIST_INIT(xenobio_cerulean_potions, list(
										/obj/item/slimepotion/enhancer,
										/obj/item/slimepotion/stabilizer,
										/obj/item/slimepotion/mutator,
										/obj/item/slimepotion/docility,
										/obj/item/slimepotion/steroid,
										/obj/item/slimepotion/unity,
										/obj/item/slimepotion/loyalty,
										/obj/item/slimepotion/friendship,
										/obj/item/slimepotion/feeding,
										/obj/item/slimepotion/infertility,
										/obj/item/slimepotion/fertility,
										/obj/item/slimepotion/shrink,
										/obj/item/slimepotion/death,
										/obj/item/slimepotion/ferality,
										/obj/item/slimepotion/reinvigoration,
										/obj/item/slimepotion/mimic,
										/obj/item/slimepotion/sapience,
										/obj/item/slimepotion/obedience))

GLOBAL_LIST_INIT(xenobio_rainbow_extracts, list(
										/obj/item/slime_extract/grey = 2,
										/obj/item/slime_extract/metal = 3,
										/obj/item/slime_extract/blue = 3,
										/obj/item/slime_extract/purple = 1,
										/obj/item/slime_extract/orange = 3,
										/obj/item/slime_extract/yellow = 3,
										/obj/item/slime_extract/gold = 3,
										/obj/item/slime_extract/silver = 3,
										/obj/item/slime_extract/dark_purple = 2,
										/obj/item/slime_extract/dark_blue = 3,
										/obj/item/slime_extract/red = 3,
										/obj/item/slime_extract/green = 3,
										/obj/item/slime_extract/pink = 3,
										/obj/item/slime_extract/oil = 3,
										/obj/item/slime_extract/bluespace = 3,
										/obj/item/slime_extract/cerulean = 1,
										/obj/item/slime_extract/amber = 3,
										/obj/item/slime_extract/sapphire = 3,
										/obj/item/slime_extract/ruby = 3,
										/obj/item/slime_extract/emerald = 3,
										/obj/item/slime_extract/light_pink = 1,
										/obj/item/slime_extract/rainbow = 1))


//// Wildlife lists
//Listed by-type. Under each type are lists of lists that contain 'groupings' of wildlife. Sorted from 1 to 5 by threat level.

GLOBAL_LIST_INIT(event_wildlife_aquatic, list(
										list(
												list(/mob/living/simple_mob/animal/passive/fish/koi = 1,
														/mob/living/simple_mob/animal/passive/fish/pike = 2,
														/mob/living/simple_mob/animal/passive/fish/perch = 2,
														/mob/living/simple_mob/animal/passive/fish/salmon = 2,
														/mob/living/simple_mob/animal/passive/fish/trout = 2,
														/mob/living/simple_mob/animal/passive/fish/bass = 3),
												list(/mob/living/simple_mob/animal/passive/fish/salmon = 1),
												list(/mob/living/simple_mob/animal/passive/fish/perch = 1),
												list(/mob/living/simple_mob/animal/passive/fish/trout = 1),
												list(/mob/living/simple_mob/animal/passive/fish/bass = 1),
												list(/mob/living/simple_mob/animal/passive/fish/pike = 1),
												list(/mob/living/simple_mob/animal/passive/crab = 1)
											),
										list(
												list(/mob/living/simple_mob/animal/sif/duck = 1),
												list(/mob/living/simple_mob/animal/passive/fish/measelshark = 1),
												list(/mob/living/simple_mob/vore/pakkun = 5,
														/mob/living/simple_mob/vore/pakkun/snapdragon = 1)
											),
										list(
												list(/mob/living/simple_mob/animal/space/goose = 10,
														/mob/living/simple_mob/animal/space/goose/white = 1),
												list(/mob/living/simple_mob/vore/alienanimals/space_jellyfish = 1)
											),
										list(
												list(/mob/living/simple_mob/animal/sif/hooligan_crab = 1)
											)
										))

GLOBAL_LIST_INIT(event_wildlife_roaming, list(
										list(
												list(/mob/living/simple_mob/animal/passive/mouse/jerboa = 1,
														/mob/living/simple_mob/animal/passive/mouse/black = 2,
														/mob/living/simple_mob/animal/passive/mouse/brown = 2,
														/mob/living/simple_mob/animal/passive/mouse/gray = 2,
														/mob/living/simple_mob/animal/passive/mouse/white = 2,
														/mob/living/simple_mob/animal/passive/mouse/rat/strong = 3),
												list(/mob/living/simple_mob/animal/passive/bird/black_bird = 1,
														/mob/living/simple_mob/animal/passive/bird/azure_tit = 1,
														/mob/living/simple_mob/animal/passive/bird/european_robin = 1,
														/mob/living/simple_mob/animal/passive/bird/goldcrest = 1,
														/mob/living/simple_mob/animal/passive/bird/ringneck_dove = 1),
												list(/mob/living/simple_mob/animal/passive/dog/corgi = 4,
														/mob/living/simple_mob/animal/passive/dog/corgi/puppy = 1),
												list(/mob/living/simple_mob/vore/rabbit = 1),
												list(/mob/living/simple_mob/vore/redpanda = 14,
														/mob/living/simple_mob/vore/redpanda/fae = 7,
														/mob/living/simple_mob/vore/redpanda/blue = 1),
												list(/mob/living/simple_mob/animal/passive/cow = 1),
												list(/mob/living/simple_mob/animal/passive/chicken = 4,
														/mob/living/simple_mob/animal/passive/chick = 1),
												list(/mob/living/simple_mob/animal/passive/snake = 2,
														/mob/living/simple_mob/animal/passive/snake/red = 1,
														/mob/living/simple_mob/animal/passive/snake/python = 1)
											),
										list(
												list(/mob/living/simple_mob/vore/horse/big = 7,
														/mob/living/simple_mob/vore/horse = 2),
												list(/mob/living/simple_mob/vore/fennix = 1,
														/mob/living/simple_mob/vore/fennec = 4),
												list(/mob/living/simple_mob/vore/bee = 1),
												list(/mob/living/simple_mob/animal/passive/fox = 1),
												list(/mob/living/simple_mob/vore/sheep = 3,
														/mob/living/simple_mob/animal/goat = 1),
												list(/mob/living/simple_mob/vore/hippo = 1),
												list(/mob/living/simple_mob/vore/alienanimals/dustjumper = 1),
												list(/mob/living/simple_mob/vore/alienanimals/teppi = 1)
											),
										list(
												list(/mob/living/simple_mob/vore/aggressive/frog = 1),
												list(/mob/living/simple_mob/tomato = 1),
												list(/mob/living/simple_mob/vore/wolf = 1),
												list(/mob/living/simple_mob/vore/aggressive/dino = 1),
												list(/mob/living/simple_mob/animal/space/bats = 1)
											),
										list(
												list(/mob/living/simple_mob/animal/space/bear = 1),
												list(/mob/living/simple_mob/vore/aggressive/deathclaw = 1),
												list(/mob/living/simple_mob/vore/otie = 1),
												list(/mob/living/simple_mob/vore/aggressive/panther = 1),
												list(/mob/living/simple_mob/vore/aggressive/rat = 1),
												list(/mob/living/simple_mob/vore/aggressive/giant_snake = 1),
												list(/mob/living/simple_mob/vore/aggressive/corrupthound = 1)
											)
										))


GLOBAL_LIST_INIT(selectable_speech_bubbles, list(
	"default",
	"normal",
	"slime",
	"comm",
	"machine",
	"synthetic",
	"synthetic_evil",
	"cyber",
	"ghost",
	"slime_green",
	"slime_yellow",
	"slime_red",
	"slime_blue",
	"dark",
	"plant",
	"clown",
	"fox",
	"latte_fox",
	"blue_fox",
	"maus",
	"wolf",
	"red_panda",
	"blue_panda",
	"tentacles",
	"heart",
	"textbox",
	"possessed", // purdev (spelling changed <3)
	"square",
	"medical",
	"medical_square",
	"cardiogram",
	"security",
	"notepad",
	"science",
	"engineering",
	"cargo"
	))



// AREA GENERATION AND BLUEPRINT STUFF BELOW HERE
// typecacheof(list) and list() are two completely separate things, don't break!

// WHATEVER YOU DO, DO NOT LEAVE THE LAST THING IN THE LIST BELOW HAVE A COMMA OR EVERYTHING EVER WILL BREAK
// ENSURE THE LAST AREA OR TURF LISTED IS SIMPLY "/area/clownhideout" AND NOT "/area/clownhideout," OR YOU WILL IMMEDIATELY DIE

// These lists are, obviously, unfinished.

// ALLOWING BUILDING IN AN AREA:
// If you want someone to be able to build a new area in a place, add the area to the 'GLOB.BUILDABLE_AREA_TYPES' and 'GLOB.blacklisted_areas'
// GLOB.BUILDABLE_AREA_TYPES means they can build an area there. The GLOB.blacklisted_areas means they CAN NOT EXPAND that area. No making space bigger!

// DISALLOW BUILDING/AREA MANIPULATION IN AN AREA (OR A TURF TYPE):
// Likewise, if you want someone to never ever EVER be able to do anything area generation/expansion related to an area
// Then add it to GLOB.SPECIALS and GLOB.area_or_turf_fail_types

// If you want someone to
GLOBAL_LIST_INIT(BUILDABLE_AREA_TYPES, list(
	/area/space,
	/area/mine
//	/area/surface/cave,		//SC
// /area/tether/surfacebase/outside,	//Downstreams, uncomment these if you are using these maps
//	/area/groundbase/unexplored/outdoors,
//	/area/maintenance/groundbase/level1,
//	/area/submap/groundbase/wilderness,
//	/area/groundbase/mining,
//	/area/offmap/aerostat/surface,
//	/area/tether_away/beach,
//	/area/tether_away/cave,
))

GLOBAL_LIST_INIT(blacklisted_areas, typecacheof(list(
	/area/space,
	/area/mine
//	/area/surface/cave,		//SC
	//TETHER STUFF BELOW THIS	//Downstreams, uncomment these if you are using these maps
//	/area/tether/surfacebase/outside,
	//GROUNDBASE STUFF BELOW THIS
//	/area/groundbase/unexplored/outdoors,
//	/area/maintenance/groundbase/level1,
//	/area/submap/groundbase/wilderness,
//	/area/groundbase/mining,
//	/area/offmap/aerostat/surface,
//	/area/tether_away/beach,
//	/area/tether_away/cave
	)))

GLOBAL_LIST_INIT(SPECIALS, list(
	/turf/space,
	/area/shuttle,
	/area/admin,
	/area/arrival,
	/area/centcom,
	/area/asteroid,
	/area/tdome,
	/area/syndicate_station,
	/area/wizard_station,
	/area/prison,
	/area/holodeck,
	/area/turbolift,
	/area/tether/elevator,
	/turf/unsimulated/wall/planetary,
	/area/submap/virgo2,
	/area/submap/casino_event,
	/area/vr
	// /area/derelict //commented out, all hail derelict-rebuilders!
))

GLOBAL_LIST_INIT(area_or_turf_fail_types, typecacheof(list(
	/turf/space,
	/area/shuttle,
	/area/admin,
	/area/arrival,
	/area/centcom,
	/area/asteroid,
	/area/tdome,
	/area/syndicate_station,
	/area/wizard_station,
	/area/prison,
	/area/holodeck,
	/turf/simulated/wall/elevator,
	/area/turbolift,
	/area/tether/elevator,
	/turf/unsimulated/wall/planetary,
	/area/submap/virgo2,
	/area/submap/casino_event,
	/area/vr
	)))

//GRIPPERS!!!
#define BASIC_GRIPPER \
	/obj/item/cell, \
	/obj/item/airlock_electronics, \
	/obj/item/tracker_electronics, \
	/obj/item/module/power_control, \
	/obj/item/bluespace_crystal, \
	/obj/item/stock_parts, \
	/obj/item/frame, \
	/obj/item/camera_assembly, \
	/obj/item/tank, \
	/obj/item/circuitboard, \
	/obj/item/smes_coil, \
	/obj/item/stack/tile, \
	/obj/item/stack/hose, \
	/obj/item/stack/animalhide, \
	/obj/item/stack/hairlesshide, \
	/obj/item/stack/wetleather

#define OMNI_GRIPPER \
	/obj/item

#define MINER_GRIPPER \
	/obj/item/cell, \
	/obj/item/stock_parts

#define SECURITY_GRIPPER \
	/obj/item/paper, \
	/obj/item/paper_bundle, \
	/obj/item/pen, \
	/obj/item/sample, \
	/obj/item/forensics/sample_kit, \
	/obj/item/taperecorder, \
	/obj/item/rectape, \
	/obj/item/uv_light

#define PAPERWORK_GRIPPER \
	/obj/item/clipboard, \
	/obj/item/paper, \
	/obj/item/paper_bundle, \
	/obj/item/card/id, \
	/obj/item/book, \
	/obj/item/newspaper

//Food reagent containers due to having to grind food.
#define MEDICAL_GRIPPER \
	/obj/item/reagent_containers/glass, \
	/obj/item/reagent_containers/food, \
	/obj/item/storage/pill_bottle, \
	/obj/item/reagent_containers/pill, \
	/obj/item/reagent_containers/blood, \
	/obj/item/nif, \
	/obj/item/stack/material/phoron, \
	/obj/item/tank/anesthetic, \
	/obj/item/disk/body_record, \

#define RESEARCH_GRIPPER \
	/obj/item/cell, \
	/obj/item/stock_parts, \
	/obj/item/mmi, \
	/obj/item/robot_parts, \
	/obj/item/borg/upgrade, \
	/obj/item/flash, \
	/obj/item/disk, \
	/obj/item/circuitboard, \
	/obj/item/reagent_containers/glass, \
	/obj/item/assembly/prox_sensor, \
	/obj/item/healthanalyzer, \
	/obj/item/slime_cube, \
	/obj/item/slime_crystal, \
	/obj/item/disposable_teleporter/slime, \
	/obj/item/slimepotion, \
	/obj/item/slime_extract, \
	/obj/item/reagent_containers/food/snacks/monkeycube, \
	/obj/item/anomaly_releaser, \
	/obj/item/research_sample

#define CIRCUIT_GRIPPER \
	/obj/item/cell/device, \
	/obj/item/electronic_assembly, \
	/obj/item/assembly/electronic_assembly, \
	/obj/item/clothing/under/circuitry, \
	/obj/item/clothing/gloves/circuitry, \
	/obj/item/clothing/glasses/circuitry, \
	/obj/item/clothing/shoes/circuitry, \
	/obj/item/clothing/head/circuitry, \
	/obj/item/clothing/ears/circuitry, \
	/obj/item/clothing/suit/circuitry, \
	/obj/item/implant/integrated_circuit, \
	/obj/item/integrated_circuit

#define SERVICE_GRIPPER \
	/obj/item/reagent_containers/glass, \
	/obj/item/reagent_containers/food, \
	/obj/item/seeds, \
	/obj/item/grown, \
	/obj/item/trash, \
	/obj/item/reagent_containers/cooking_container, \
	/obj/item/spacecasinocash, \
	/obj/item/spacecasinocash_fake, \
	/obj/item/deck/cards, \
	/obj/item/hand

#define GRAVEYARD_GRIPPER \
	/obj/item/seeds, \
	/obj/item/grown, \
	/obj/item/material/gravemarker

#define SCENE_GRIPPER \
	/obj/item/capture_crystal, \
	/obj/item/clothing, \
	/obj/item/implanter, \
	/obj/item/disk/nifsoft/compliance, \
	/obj/item/handcuffs, \
	/obj/item/toy, \
	/obj/item/petrifier, \
	/obj/item/dice, \
	/obj/item/casino_platinum_chip, \
	/obj/item/spacecasinocash, \
	/obj/item/spacecasinocash_fake, \
	/obj/item/hand, \
	/obj/item/pen, \
	/obj/item/leash, \
	/obj/item/paper, \
	/obj/item/a_gift, \
	/obj/item/remote_scene_tool, \


#define ORGAN_GRIPPER \
	/obj/item/organ, \
	/obj/item/nif

#define ROBOTICS_ORGAN_GRIPPER \
	/obj/item/organ/external, \
	/obj/item/organ/internal/brain, \
	/obj/item/organ/internal/cell, \
	/obj/item/organ/internal/eyes/robot, \
	/obj/item/nif

#define EXOSUIT_GRIPPER \
	/obj/item/mecha_parts/part, \
	/obj/item/mecha_parts/micro/part, \
	/obj/item/mecha_parts/mecha_equipment, \
	/obj/item/mecha_parts/mecha_tracking, \
	/obj/item/mecha_parts/component

#define SHEET_GRIPPER \
	/obj/item/stack/material, \
	/obj/item/stack/rods

GLOBAL_LIST_INIT(all_borg_multitool_options, list(
	/obj/item/tool/screwdriver/cyborg,
	/obj/item/tool/wrench/cyborg,
	/obj/item/tool/crowbar/cyborg,
	/obj/item/tool/wirecutters/cyborg,
	/obj/item/multitool/cyborg,
	/obj/item/weldingtool/electric/mounted/cyborg,
	/obj/item/surgical/retractor/cyborg,
	/obj/item/surgical/hemostat/cyborg,
	/obj/item/surgical/cautery/cyborg,
	/obj/item/surgical/surgicaldrill/cyborg,
	/obj/item/surgical/scalpel/cyborg,
	/obj/item/surgical/circular_saw/cyborg,
	/obj/item/surgical/bonegel/cyborg,
	/obj/item/surgical/FixOVein/cyborg,
	/obj/item/surgical/bonesetter/cyborg,
	/obj/item/surgical/bioregen/cyborg,
	/obj/item/autopsy_scanner,
	/obj/item/material/minihoe/cyborg,
	/obj/item/material/knife/machete/hatchet/cyborg,
	/obj/item/analyzer/plant_analyzer/cyborg,
	/obj/item/material/knife/cyborg,
	/obj/item/robot_harvester,
	/obj/item/material/kitchen/rollingpin/cyborg,
	/obj/item/reagent_containers/spray,
))

GLOBAL_LIST_INIT(material_synth_list, list(
								METAL_SYNTH = /datum/matter_synth/metal,
								PLASTEEL_SYNTH = /datum/matter_synth/plasteel,
								GLASS_SYNTH = /datum/matter_synth/glass,
								WOOD_SYNTH = /datum/matter_synth/wood,
								PLASTIC_SYNTH = /datum/matter_synth/plastic,
								WIRE_SYNTH = /datum/matter_synth/wire,
								CLOTH_SYNTH = /datum/matter_synth/cloth
							))

GLOBAL_LIST_EMPTY(virusDB) // Stores discovered viruses

///Medications that speed up your heartrate
GLOBAL_LIST_INIT(tachycardics, list(
									REAGENT_ID_COFFEE,
									REAGENT_ID_INAPROVALINE,
									REAGENT_ID_HYPERZINE,
									REAGENT_ID_NITROGLYCERIN,
									REAGENT_ID_THIRTEENLOKO,
									REAGENT_ID_NICOTINE
									))

///Medications that slow down your heartrate
GLOBAL_LIST_INIT(bradycardics, list(
									REAGENT_ID_NEUROTOXIN,
									REAGENT_ID_CRYOXADONE,
									REAGENT_ID_CLONEXADONE,
									REAGENT_ID_BLISS,
									REAGENT_ID_STOXIN,
									REAGENT_ID_AMBROSIAEXTRACT
									))

///Medications that stop your heart
GLOBAL_LIST_INIT(heartstopper, list(
									REAGENT_ID_POTASSIUMCHLOROPHORIDE,
									REAGENT_ID_ZOMBIEPOWDER
									))

///Medications that stop your heart under certain conditions.
GLOBAL_LIST_INIT(cheartstopper, list(
									REAGENT_ID_POTASSIUMCHLORIDE
									))
