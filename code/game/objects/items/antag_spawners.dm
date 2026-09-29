/obj/item/antag_spawner
	w_class = ITEMSIZE_TINY
	var/used = 0
	var/ghost_query_type = null
	var/searching = FALSE
	var/datum/effect/effect/system/spark_spread/sparks
	var/datum/ghost_query/Q //This is used so we can unregister ourself.

/obj/item/antag_spawner/Initialize(mapload)
	. = ..()
	sparks.set_up(5, 0, src)
	sparks.attach(loc)

DECLARE_DEFAULT_CHILD(/obj/item/antag_spawner, "sparks", /datum/effect/effect/system/spark_spread)
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

	own_set(src, "Q", new ghost_query_type())
	om_hook(Q, /datum/om/event/ghost_query_complete, src, PROC_REF(get_winner))
	Q.query()

/obj/item/antag_spawner/proc/get_winner(datum/source, datum/om/event/ghost_query_complete/event)
	EVENT_HANDLER
	if(Q && Q.candidates.len)
		var/mob/observer/dead/D = Q.candidates[1]
		spawn_antag(D.client, get_turf(src))
	else
		reset_search()
	om_unhook(Q, /datum/om/event/ghost_query_complete, src)
	own_clear(src, "Q", OWN_DELETE) //get rid of the query
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

DECLARE_INTERACTIONS(/obj/item/antag_spawner/technomancer_apprentice, INTERACT_USE(null, PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/antag_spawner/technomancer_apprentice/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	to_chat(user, span_notice("Teleporter attempting to lock on to your apprentice."))
	request_player()
	return TRUE

/obj/item/antag_spawner/technomancer_apprentice/request_player()
	icon_state = "oldshieldon"
	..()

/obj/item/antag_spawner/technomancer_apprentice/reset_search()
	..()
	if(!used)
		icon_state = "oldshieldoff"
		visible_message(span_warning("The teleporter failed to find the apprentice.  Perhaps another attempt could be made later?"))

/obj/item/antag_spawner/technomancer_apprentice/spawn_antag(client/C, turf/T)
	sparks.start()
	var/mob/living/carbon/human/H = new/mob/living/carbon/human(T)
	C.prefs.copy_to(H)
	H.key = C.key

	to_chat(H, span_infoplain(span_bold("You are the Technomancer's apprentice! Your goal is to assist them in their mission at the [station_name()].")))
	to_chat(H, span_infoplain(span_bold("Your service has not gone unrewarded, however. Studying under them, you have learned how to use a Manipulation Core \
	of your own. You also have a catalog, to purchase your own functions and equipment as you see fit.")))
	to_chat(H, span_infoplain(span_bold("It would be wise to speak to your master, and learn what their plans are for today.")))

	om_after(src, 0.1 SECONDS, PROC_REF(finish_technomancer_spawn), H)

/obj/item/antag_spawner/technomancer_apprentice/proc/finish_technomancer_spawn(mob/living/carbon/human/H)
	GLOB.technomancers.add_antagonist(H.mind, 0, 1, 0, 0, 0)
	equip_antag(H)
	used = 1
	consume(src, H)

/obj/item/antag_spawner/technomancer_apprentice/equip_antag(mob/technomancer_mob)
	var/datum/antagonist/technomancer/antag_datum = GLOB.antag_service.all_antag_types[MODE_TECHNOMANCER]
	antag_datum.equip_apprentice(technomancer_mob)

/obj/item/antag_spawner/syndicate_drone
	name = "drone teleporter"
	desc = "A teleportation device, which will bring a powerful and loyal drone to you."
	icon = 'icons/obj/objects.dmi'
	icon_state = "oldshieldoff"
	ghost_query_type = /datum/ghost_query/syndicate_drone
	var/drone_type = null

DECLARE_INTERACTIONS(/obj/item/antag_spawner/syndicate_drone, INTERACT_USE(null, PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/antag_spawner/syndicate_drone/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	to_chat(user, span_notice("Teleporter attempting to lock on to an available unit."))
	request_player()
	return TRUE

/obj/item/antag_spawner/syndicate_drone/request_player()
	icon_state = "oldshieldon"
	..()

/obj/item/antag_spawner/syndicate_drone/reset_search()
	..()
	if(!used)
		icon_state = "oldshieldoff"
		visible_message(span_warning("The teleporter failed to find any available.  Perhaps another attempt could be made later?"))

/obj/item/antag_spawner/syndicate_drone/spawn_antag(client/C, turf/T)
	sparks.start()
	var/mob/living/silicon/robot/R = new drone_type(T)

	// Put this text here before ckey change so that their laws are shown below it, since borg login() shows it.
	to_chat(C, span_notice("You are a " + span_bold("Mercenary Drone") + ", activated to serve your team."))
	to_chat(C, span_notice(span_bold("Be sure to examine your currently loaded lawset closely.") + " It would be wise \
	to speak with your team, and learn what their plan is for today."))

	R.key = C.key

	om_after(src, 0.1 SECONDS, PROC_REF(finish_drone_spawn), R)

/obj/item/antag_spawner/syndicate_drone/proc/finish_drone_spawn(mob/living/silicon/robot/R)
	GLOB.mercs.add_antagonist(R.mind, FALSE, TRUE, FALSE, FALSE, FALSE)
	consume(src, R)

/obj/item/antag_spawner/syndicate_drone/protector
	drone_type = /mob/living/silicon/robot/syndicate/protector

/obj/item/antag_spawner/syndicate_drone/combat_medic
	drone_type = /mob/living/silicon/robot/syndicate/combat_medic

/obj/item/antag_spawner/syndicate_drone/mechanist
	drone_type = /mob/living/silicon/robot/syndicate/mechanist
