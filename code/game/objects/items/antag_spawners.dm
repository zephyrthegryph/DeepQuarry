/obj/item/antag_spawner
	w_class = ITEMSIZE_TINY
	var/used = 0
	var/ghost_query_type = null
	var/searching = FALSE
	var/datum/ghost_query/Q //This is used so we can unregister ourself.

CAPABILITIES(/obj/item/antag_spawner)
	owns_one(nameof(Q), /datum/ghost_query)

/obj/item/antag_spawner/proc/spawn_antag(client/C, turf/T)
	return

/obj/item/antag_spawner/proc/equip_antag(mob/target)
	return

/obj/item/antag_spawner/proc/request_player()
	if(!ghost_query_type)
		return
	if(searching)
		return // Already searching.
	searching = TRUE

	rel_set(src, nameof(Q), new ghost_query_type())
	observe(Q, /datum/notice/ghost_query_complete, src, then(PROC_REF(get_winner)))
	Q.query()

/obj/item/antag_spawner/proc/get_winner(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	if(Q && Q.candidates.len)
		var/mob/observer/dead/D = Q.candidates[1]
		spawn_antag(D.client, get_turf(src))
	else
		reset_search()
	unobserve(Q, /datum/notice/ghost_query_complete, src)
	rel_clear(src, nameof(Q)) //get rid of the query
	return

/obj/item/antag_spawner/proc/reset_search()
	searching = FALSE
	return

/obj/item/antag_spawner/technomancer_apprentice
	name = "apprentice teleporter"
	desc = "A teleportation device, which will bring a less potent manipulator of space to you."
	icon = 'icons/obj/objects.dmi'
	icon_state = "oldshieldoff"
	ghost_query_type = /datum/ghost_query/apprentice

CAPABILITIES(/obj/item/antag_spawner/technomancer_apprentice)
	op("activate", in_hand(), then(PROC_REF(activated)))

/// The original held activation feedback and its downstream behavior.
/obj/item/antag_spawner/technomancer_apprentice/proc/activated(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_notice("Teleporter attempting to lock on to your apprentice."))
	request_player()
	return OP_OK

/obj/item/antag_spawner/technomancer_apprentice/request_player()
	icon_state = "oldshieldon"
	..()

/obj/item/antag_spawner/technomancer_apprentice/reset_search()
	..()
	if(!used)
		icon_state = "oldshieldoff"
		visible_message(span_warning("The teleporter failed to find the apprentice.  Perhaps another attempt could be made later?"))

/obj/item/antag_spawner/technomancer_apprentice/spawn_antag(client/C, turf/T)
	fx_sparks(src, 5, FALSE)
	var/mob/living/carbon/human/H = new/mob/living/carbon/human(T)
	C.prefs.copy_to(H)
	H.key = C.key

	to_chat(H, span_infoplain(span_bold("You are the Technomancer's apprentice! Your goal is to assist them in their mission at the [station_name()].")))
	to_chat(H, span_infoplain(span_bold("Your service has not gone unrewarded, however. Studying under them, you have learned how to use a Manipulation Core \
	of your own. You also have a catalog, to purchase your own functions and equipment as you see fit.")))
	to_chat(H, span_infoplain(span_bold("It would be wise to speak to your master, and learn what their plans are for today.")))

	after(src, 0.1 SECONDS, PROC_REF(finish_technomancer_spawn), with = list(H))

/obj/item/antag_spawner/technomancer_apprentice/proc/finish_technomancer_spawn(mob/living/carbon/human/H)
	if(!QDELETED(H))
		GLOB.technomancers.add_antagonist(H.mind, 0, 1, 0, 0, 0)
		equip_antag(H)
	used = 1
	consume(src, H)

/obj/item/antag_spawner/technomancer_apprentice/equip_antag(mob/technomancer_mob)
	var/datum/antagonist/technomancer/antag_datum = SSantag.all_antag_types[MODE_TECHNOMANCER]
	antag_datum.equip_apprentice(technomancer_mob)

/obj/item/antag_spawner/syndicate_drone
	name = "drone teleporter"
	desc = "A teleportation device, which will bring a powerful and loyal drone to you."
	icon = 'icons/obj/objects.dmi'
	icon_state = "oldshieldoff"
	ghost_query_type = /datum/ghost_query/syndicate_drone
	var/drone_type = null

CAPABILITIES(/obj/item/antag_spawner/syndicate_drone)
	op("activate", in_hand(), then(PROC_REF(activated)))

/// The original held activation feedback and its downstream behavior.
/obj/item/antag_spawner/syndicate_drone/proc/activated(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_notice("Teleporter attempting to lock on to an available unit."))
	request_player()
	return OP_OK

/obj/item/antag_spawner/syndicate_drone/request_player()
	icon_state = "oldshieldon"
	..()

/obj/item/antag_spawner/syndicate_drone/reset_search()
	..()
	if(!used)
		icon_state = "oldshieldoff"
		visible_message(span_warning("The teleporter failed to find any available.  Perhaps another attempt could be made later?"))

/obj/item/antag_spawner/syndicate_drone/spawn_antag(client/C, turf/T)
	fx_sparks(src, 5, FALSE)
	var/mob/living/silicon/robot/R = new drone_type(T)

	// Put this text here before ckey change so that their laws are shown below it, since borg login() shows it.
	to_chat(C, span_notice("You are a " + span_bold("Mercenary Drone") + ", activated to serve your team."))
	to_chat(C, span_notice(span_bold("Be sure to examine your currently loaded lawset closely.") + " It would be wise \
	to speak with your team, and learn what their plan is for today."))

	R.key = C.key

	after(src, 0.1 SECONDS, PROC_REF(finish_drone_spawn), with = list(R))

/obj/item/antag_spawner/syndicate_drone/proc/finish_drone_spawn(mob/living/silicon/robot/R)
	if(!QDELETED(R))
		GLOB.mercs.add_antagonist(R.mind, FALSE, TRUE, FALSE, FALSE, FALSE)
	consume(src, R)

/obj/item/antag_spawner/syndicate_drone/protector
	drone_type = /mob/living/silicon/robot/syndicate/protector

/obj/item/antag_spawner/syndicate_drone/combat_medic
	drone_type = /mob/living/silicon/robot/syndicate/combat_medic

/obj/item/antag_spawner/syndicate_drone/mechanist
	drone_type = /mob/living/silicon/robot/syndicate/mechanist
