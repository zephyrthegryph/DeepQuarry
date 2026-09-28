/obj/structure/trash_pile
	name = "trash pile"
	desc = "A heap of garbage, but maybe there's something interesting inside?"
	icon = 'icons/obj/trash_piles.dmi'
	icon_state = "randompile"
	density = TRUE
	anchored = TRUE

	var/list/searchedby	= list()// Characters that have searched this trashpile, with values of searched time.
	var/mob/living/hider		// A simple animal that might be hiding in the pile
	var/obj/structure/mob_spawner/mouse_nest/mouse_nest = null

/obj/structure/trash_pile/Initialize(mapload)
	. = ..()
	icon_state = pick(
		"pile1",
		"pile2",
		"pilechair",
		"piletable",
		"pilevending",
		"brtrashpile",
		"microwavepile",
		"rackpile",
		"boxfort",
		"trashbag",
		"brokecomp")
	mouse_nest = new(src)
	AddElement(/datum/element/lootable/trash_pile)
	AddElement(/datum/element/climbable)

REF_OWNED(/obj/structure/trash_pile, "mouse_nest")

/obj/structure/trash_pile/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_item/trash_pile_item,
		/datum/interaction/entry_hand/trash_pile_search,
	)
	..()

/// Old attackby: dropping gamma loot into the pile restores it.
/datum/interaction/entry_item/trash_pile_item
	id = "trash_pile_item"
	name = "Use"
	effect = /obj/structure/trash_pile/proc/interaction_item

/obj/structure/trash_pile/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	var/w_type = W.type
	if(w_type in GLOB.allocated_gamma_loot)
		to_chat(user,span_notice("You feel \the [W] slip from your hand, and disappear into the trash pile."))
		user.unEquip(W)
		W.forceMove(src)
		restore_gamma_loot(w_type)
		consume(W, user)
	return TRUE

/obj/structure/trash_pile/attack_generic(mob/user)
	//Simple Animal
	if(isanimal(user))
		var/mob/living/L = user
		//They're in it, and want to get out.
		if(L.loc == src)
			om_prompt(src, user, list("message" = "Do you want to exit \the [src]?", "title" = "Un-Hide?", "choices" = list("Exit","Stay"), "requires" = list(/datum/om/check/inside_target)), PROC_REF(hide_answered))
		else if(!hider)
			om_prompt(src, user, list("message" = "Do you want to hide in \the [src]?", "title" = "Un-Hide?", "choices" = list("Hide","Stay"), "requires" = PROMPT_ADJACENT), PROC_REF(hide_answered))
	else
		return ..()

/obj/structure/trash_pile/proc/hide_answered(mob/living/L, choice, datum/om/prompt/ask)
	if(choice == "Exit")
		if(L == hider)
			hider = null
		L.forceMove(get_turf(src))
	else if(choice == "Hide" && !hider) //Check again because PROMPT
		L.forceMove(src)
		hider = L

/obj/structure/trash_pile/attack_ghost(mob/observer/user as mob)
	if(CONFIG_GET(flag/disable_player_mice))
		to_chat(user, span_warning("Spawning as a mouse is currently disabled."))
		return

	if(jobban_isbanned(user, JOB_GHOSTROLES))
		to_chat(user, span_warning("You cannot become a mouse because you are banned from playing ghost roles."))
		return

	if(!user.MayRespawn(TRUE))
		return

	var/turf/T = get_turf(src)
	if(!T || (T.z in using_map.admin_levels))
		to_chat(user, span_warning("You may not spawn as a mouse on this Z-level."))
		return

	var/timedifference = world.time - user.client.time_died_as_mouse
	if(user.client.time_died_as_mouse && timedifference <= CONFIG_GET(number/mouse_respawn_time) MINUTES)
		var/timedifference_text
		timedifference_text = time2text(CONFIG_GET(number/mouse_respawn_time) MINUTES - timedifference,"mm:ss")
		to_chat(user, span_warning("You may only spawn again as a mouse more than [CONFIG_GET(number/mouse_respawn_time)] minutes after your death. You have [timedifference_text] left."))
		return

	om_prompt(src, user, list("message" = "Are you -sure- you want to become a mouse?", "title" = "Are you sure you want to squeek?", "choices" = list("Squeek!","Nope!"), "requires" = list(/datum/om/check/has_client)), PROC_REF(mouse_confirmed))

/obj/structure/trash_pile/proc/mouse_confirmed(mob/observer/user, response, datum/om/prompt/ask)
	if(response != "Squeek!" || !isobserver(user)) return  //Hit the wrong key...again.

	var/mob/living/simple_mob/animal/passive/mouse/host
	host = new /mob/living/simple_mob/animal/passive/mouse(get_turf(src))

	if(host)
		if(CONFIG_GET(flag/uneducated_mice))
			host.universal_understand = 0
		announce_ghost_joinleave(src, 0, "They are now a mouse.")
		host.ckey = user.ckey
		to_chat(host, span_info("You are now a mouse. Try to avoid interaction with players, and do not give hints away that you are more than a simple rodent."))

	var/atom/A = get_holder_at_turf_level(src)
	A.visible_message("[host] crawls out of \the [src].")
	return

/// Old attack_hand: search the pile.
/datum/interaction/entry_hand/trash_pile_search
	id = "trash_pile_search"
	name = "Search"
	effect = /obj/structure/trash_pile/proc/interaction_search

/obj/structure/trash_pile/proc/interaction_search(mob/user, obj/item/held, datum/interaction/interaction)
	//Human mob
	if(ishuman(user))
		var/mob/living/carbon/human/H = user

		if(om_busy(src)) // a search claims the pile
			to_chat(H, span_warning("\The [src] is already being searched."))
			return TRUE

		H.visible_message("[user] searches through \the [src].",span_notice("You search through \the [src]."))
		if(hider)
			to_chat(hider,span_warning("[user] is searching the trash pile you're in!"))

		//Do the searching
		om_do_after(user, rand(4 SECONDS,6 SECONDS), target = src, receiver = src, on_done = PROC_REF(attack_hand_timed_done), done_args = list(user), claims = TRUE)
	return TRUE

/obj/structure/trash_pile/proc/attack_hand_timed_done(mob/user)
	if(hider && prob(50))
		//If there was a hider, chance to reveal them
		to_chat(hider,span_danger("You've been discovered!"))
		hider.forceMove(get_turf(src))
		hider = null
		to_chat(user,span_danger("Some sort of creature leaps out of \the [src]!"))
	else
		SEND_SIGNAL(src,COMSIG_LOOT_REWARD,user,searchedby, 5)

/obj/structure/mob_spawner/mouse_nest
	name = "trash"
	desc = "A small heap of trash, perfect for mice and other pests to nest in."
	icon = 'icons/obj/trash_piles.dmi'
	icon_state = "randompile"
	spawn_types = list(
	/mob/living/simple_mob/animal/passive/mouse= 100,
	/mob/living/simple_mob/animal/passive/cockroach = 25)
	simultaneous_spawns = 1
	destructible = 1
	spawn_delay = 1 HOUR

/obj/structure/mob_spawner/mouse_nest/Initialize(mapload)
	. = ..()
	last_spawn = rand(world.time - spawn_delay, world.time)
	icon_state = pick(
		"pile1",
		"pile2",
		"pilechair",
		"piletable",
		"pilevending",
		"brtrashpile",
		"microwavepile",
		"rackpile",
		"boxfort",
		"trashbag",
		"brokecomp")

/obj/structure/mob_spawner/mouse_nest/do_spawn(mob_path)
	. = ..()
	var/atom/A = get_holder_at_turf_level(src)
	A.visible_message("[.] crawls out of \the [src].")

/obj/structure/mob_spawner/mouse_nest/get_death_report(mob/living/L)
	..()
	last_spawn = rand(world.time - spawn_delay, world.time)
