
/mob/observer/blob
	name = "Blob Overmind"
	real_name = "Blob Overmind"
	desc = "The overmind. It controls the blob."
	icon = 'icons/mob/blob.dmi'
	icon_state = "marker"
	mouse_opacity = 1
	see_in_dark = 8
	invisibility = INVISIBILITY_OBSERVER

	var/tmp/obj/structure/blob/core/blob_core	// The blob overmind's core
	var/blob_points = 0
	var/max_blob_points = 200
	var/last_attack = 0
	var/datum/blob_type/blob_type = null
	/// Relation list (REL_LIST): spores and other blob mobs this overmind spawned.
	var/list/blob_mobs
	var/list/resource_blobs = list() // ALLOW(instance_list): d: per-mob resource_blobs, filled at runtime; mobs are few
	var/placed = 0
	var/base_point_rate = 2 //for blob core placement
	var/ai_controlled = TRUE
	var/auto_pilot = FALSE // If true, and if a client is attached, the AI routine will continue running.


	var/tmp/datum/language/default_language_static

CAPABILITIES(/mob/observer/blob)
	op("auto_attack", menu(desc = "Automatically tries to kill whatever's attacking you."), label("Auto Attack (4)"), needs(req_self()), then(PROC_REF(auto_attack_op)))
	op("expand_blob_power", menu(desc = "Attempts to create a new blob in this tile. If the tile isn't clear, instead attacks it, damaging mobs and objects."), label("Expand/Attack Blob (4)"), needs(req_self()), then(PROC_REF(expand_blob_power_op)))
	op("auto_node", menu(desc = "Automatically places a node blob at a sufficent distance."), label("Auto Node Blob (100)"), needs(req_self(), req(PROC_REF(auto_node_ready))), then(PROC_REF(auto_node_op)))
	op("create_node", menu(desc = "Create a node, which will expand blobs around it, and power nearby factory and resource blobs."), label("Create Node Blob (100)"), needs(req_self(), req(PROC_REF(create_node_ready))), then(PROC_REF(create_node_op)))
	op("auto_factory", menu(desc = "Automatically places a resource tower near a node or your core, at a sufficent distance."), label("Auto Factory Blob (60)"), needs(req_self(), req(PROC_REF(auto_factory_ready))), then(PROC_REF(auto_factory_op)))
	op("create_factory", menu(desc = "Create a spore tower that will spawn spores to harass your enemies."), label("Create Factory Blob (60)"), needs(req_self(), req(PROC_REF(create_factory_ready))), then(PROC_REF(create_factory_op)))
	op("auto_resource", menu(desc = "Automatically places a resource tower near a node or your core, at a sufficent distance."), label("Auto Resource Blob (40)"), needs(req_self(), req(PROC_REF(auto_resource_ready))), then(PROC_REF(auto_resource_op)))
	op("create_resource", menu(desc = "Create a resource tower which will generate resources for you."), label("Create Resource Blob (40)"), needs(req_self(), req(PROC_REF(create_resource_ready))), then(PROC_REF(create_resource_op)))
	op("create_shield_power", menu(desc = "Create a shield blob, which is hard to kill."), label("Create Shield Blob (15)"), needs(req_self()), then(PROC_REF(create_shield_power_op)))
	op("transport_core", menu(desc = "Move your camera to your core."), label("Jump to Core"), needs(req_self()), then(PROC_REF(transport_core_op)))
	configure(mob_rules(faction = FACTION_BLOB))
	rolls(nameof(name), PROC_REF(roll_overmind_name))
	rolls(nameof(real_name), PROC_REF(roll_overmind_real_name), from = list(nameof(name)))
	knows(LANGUAGE_ANIMAL, default = TRUE)
	setup(PROC_REF(tint_overmind))
	configure(mob_rules(universal_understand = TRUE))
	ref_one(nameof(blob_core), /obj/structure/blob/core)
	owns_one(nameof(blob_type), /datum/blob_type, starts = PROC_REF(make_blob_type))
	param(nameof(placed), pos = 1)
	param(nameof(blob_points), pos = 2, default = 60)
	param(nameof(desired_blob_type), pos = 3)

/mob/observer/blob/get_default_language()
	return default_language()

/// The blob type an overmind is made as (its constructor param), or null for a random one.
/mob/observer/blob/var/desired_blob_type

/// An overmind is numbered (rolls(), before any init code reads its name): "Blob Overmind (417)".
/mob/observer/blob/proc/roll_overmind_name(datum/roller/R, target)
	return "[initial(name)] ([R.number(1, 999)])"

/// Its real name is the numbered name it rolled.
/mob/observer/blob/proc/roll_overmind_real_name(datum/roller/R, target)
	return name

/// The language an overmind speaks when it names none is the one it learned first (knows(default = TRUE)).
/mob/observer/blob/lifeform_default_language(language)
	default_language_static = GLOB.all_languages[language]

/// It takes its blob type's colour, and its core draws the same (a setup() hook, once its blob type exists).
/mob/observer/blob/proc/tint_overmind()
	color = blob_type.complementary_color
	if(blob_core())
		blob_core().sync_overmind_look() // the core draws the new type's colour

/// The starting blob type (owns_one(starts =)): the one asked for, else any.
/mob/observer/blob/proc/make_blob_type(current)
	var/datum/blob_type/BT = desired_blob_type || pick(subtypesof(/datum/blob_type))
	return new BT()

REGISTRY_MEMBERSHIP(/mob/observer/blob, REGISTRY_OVERMINDS)

// its blobs and spores lose their overmind and recolour.
/mob/observer/blob/on_destroy(force)
	for(var/obj/structure/blob/B as anything in REGISTRY_MEMBERS(REGISTRY_BLOBS))
		if(B && B.overmind == src)
			rel_clear(B, nameof(B.overmind))
			B.sync_overmind_look() //reset anything that was ours

	for(var/mob/living/simple_mob/blob/spore/BM as anything in blob_mobs)
		if(BM)
			rel_clear(BM, nameof(BM.overmind))
			BM.update_icons()

	..()

/mob/observer/blob/get_status_tab_items()
	. = ..()
	. += ""
	. += "BLOB STATUS"
	if(blob_core())
		. += "Core Health: [blob_core().get_integrity()]"
	. += "Power Stored: [blob_points]/[max_blob_points]"
	. += "Total Blobs: [REGISTRY_COUNT(REGISTRY_BLOBS)]"

/mob/observer/blob/Move(atom/NewLoc, Dir = 0)
	if(placed)
		var/obj/structure/blob/B = (locate_in_list(view("5x5", NewLoc), /obj/structure/blob))
		if(B)
			forceMove(NewLoc)
			return TRUE
		else
			return FALSE
	else
		var/area/A = get_area(NewLoc)
		if(istype(NewLoc, /turf/space) || istype(A, /area/shuttle)) //if unplaced, can't go on shuttles or space tiles
			return FALSE
		forceMove(NewLoc)
		return TRUE

/mob/observer/blob/proc/add_points(points)
	set_blob_points(between(0, blob_points + points, max_blob_points))

/mob/observer/blob/upkeep()
	..()
	if(ai_controlled && (!client || auto_pilot))
		if(prob(blob_type.ai_aggressiveness))
			auto_attack()

		if(blob_points >= 100)
			if(!auto_factory() && !auto_resource())
				auto_node()

/mob/observer/blob/say(message, datum/language/speaking = null, whispering = 0)
	message = sanitize(message)

	if(!message)
		return

	//If you're muted for IC chat
	if(client)
		if(message)
			client.handle_spam_prevention(MUTE_IC)
			if((client.prefs.muted & MUTE_IC))
				to_chat(src, span_warning("You cannot speak in IC (Muted)."))
				return

	//These will contain the main receivers of the message
	var/list/listening = list()
	var/list/listening_obj = list()

	var/turf/T = get_turf(src)
	if(T)
		//Obtain the mobs and objects in the message range
		var/list/results = get_mobs_and_objs_in_view_fast(T, world.view, remote_ghosts = client ? TRUE : FALSE)
		listening = results["mobs"]
		listening_obj = results["objs"]
	else
		return 1 //If we're in nullspace, then forget it.

	var/list/message_pieces = parse_languages(message)
	if(istype(message_pieces, /datum/multilingual_say_piece)) // Little quirk for dealing with hivemind/signlang languages.
		var/datum/multilingual_say_piece/S = message_pieces // Yay for BYOND's hilariously broken typecasting for allowing us to do this.
		S.speaking.broadcast(src, S.message)
		return 1

	if(!LAZYLEN(message_pieces))
		log_runtime(EXCEPTION("Message failed to generate pieces. [message] - [json_encode(message_pieces)]"))
		return 0

	//Handle nonverbal languages here
	for(var/datum/multilingual_say_piece/S in message_pieces)
		if(S.speaking.flags & NONVERBAL)
			custom_emote(VISIBLE_MESSAGE, "[pick(S.speaking.signlang_verb)].")

	for(var/mob/M in listening)
		if(get_dist(M, src) <= world.view || (M.stat == DEAD && !sparse_get_or(src, forbid_seeing_deadchat, FALSE)))
			M.hear_say(message_pieces, "conveys", (mob_rules_of(M).faction == blob_type.faction), src)

	//Object message delivery
	for(var/obj/O in listening_obj)
		var/dst = get_dist(get_turf(O),get_turf(src))
		if(dst <= world.view)
			O.hear_talk(src, message_pieces, "conveys")

	log_talk(message, LOG_SAY)
	return 1


/// The blob overmind's core
/mob/observer/blob/proc/blob_core() as /obj/structure/blob/core
	return blob_core

/// The shared (registered) language this overmind speaks.
/mob/observer/blob/proc/default_language() as /datum/language
	return default_language_static

// blob_type is owned (implicit OWN, rel_set in Initialize); blob_mobs is paired in simple_mob/blob.dm.
