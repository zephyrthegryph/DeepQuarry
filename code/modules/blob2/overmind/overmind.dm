
/mob/observer/blob
	name = "Blob Overmind"
	real_name = "Blob Overmind"
	desc = "The overmind. It controls the blob."
	icon = 'icons/mob/blob.dmi'
	icon_state = "marker"
	mouse_opacity = 1
	see_in_dark = 8
	invisibility = INVISIBILITY_OBSERVER

	faction = FACTION_BLOB
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

	universal_understand = TRUE

	var/tmp/datum/language/default_language_static

CAPABILITIES(/mob/observer/blob)
	owns_one(nameof(blob_type), /datum/blob_type, starts = PROC_REF(make_blob_type))
	param(nameof(placed), pos = 1)
	param(nameof(blob_points), pos = 2, default = 60)
	param(nameof(desired_blob_type), pos = 3)

/mob/observer/blob/get_default_language()
	return default_language()

/// The languages the overmind knows.
TYPE_TABLE_DECLARE(/mob/observer/blob, blob_langs, list(LANGUAGE_ANIMAL))

/// The blob type an overmind is made as (its constructor param), or null for a random one.
/mob/observer/blob/var/desired_blob_type

// ALLOW(init/INSTANCE_STATE): an overmind is numbered, makes its blob type and learns its languages before its parents' init
/mob/observer/blob/Initialize(mapload)
	var/new_name = "[initial(name)] ([rand(1, 999)])"
	name = new_name
	real_name = new_name
	for(var/L in TYPE_TABLE_GET(src, blob_langs))
		languages |= GLOB.all_languages[L]
	if(languages.len)
		default_language_static = languages[1]

	. = ..()
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
	blob_points = between(0, blob_points + points, max_blob_points)

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
		if(get_dist(M, src) <= world.view || (M.stat == DEAD && !forbid_seeing_deadchat))
			M.hear_say(message_pieces, "conveys", (M.faction == blob_type.faction), src)

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
