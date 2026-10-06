/obj/structure/trash_pile
	name = "trash pile"
	desc = "A heap of garbage, but maybe there's something interesting inside?"
	icon = 'icons/obj/trash_piles.dmi'
	icon_state = "randompile"
	density = TRUE
	anchored = TRUE
	loot_decl = LOOT_REF(/loot/trash_pile)

	// ALLOW(instance_list): d: passed to the lootable element, which adds the searcher's ckey to it in place
	var/list/searchedby	= list()// Characters that have searched this trashpile, with values of searched time.
	var/mob/living/hider		// A simple animal that might be hiding in the pile
	var/obj/structure/mob_spawner/mouse_nest/mouse_nest = null

CAPABILITIES(/obj/structure/trash_pile)
	extend(/datum/act/hit/generic, instead(then(PROC_REF(smashed_by))))
	climb()
	owns_one(nameof(mouse_nest), starts = /obj/structure/mob_spawner/mouse_nest)
	rolls(nameof(icon_state), PROC_REF(roll_icon_state))

/// Rolled before init (rolls()): what the pile looks like.
/obj/structure/trash_pile/proc/roll_icon_state(datum/roller/R)
	return R.choose(list("pile1", "pile2", "pilechair", "piletable", "pilevending", "brtrashpile", "microwavepile", "rackpile", "boxfort", "trashbag", "brokecomp"))

/obj/structure/trash_pile/declare_interactions(list/into)
	var/static/list/actor_specs = list(
		INTERACT_OBSERVER("Become mouse", PROC_REF(trash_pile_ghost_mouse)),
	)
	for(var/actor_spec in actor_specs)
		into += dq_interaction_from_spec(type, actor_spec)
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

/// A simple mob's (or a xeno's) generic hit on it, taken over (the hit/generic action): HOOK_DECLINE lets the default generic attack land.
/obj/structure/trash_pile/proc/smashed_by(datum/act/hit/generic/A)
	var/mob/user = A.attacker
	//Simple Animal
	if(isanimal(user))
		var/mob/living/L = user
		//They're in it, and want to get out.
		if(L.loc == src)
			open_request(src, /datum/prompt/yes_no, PROC_REF(exit_answered), answerer = user, title = "Un-Hide?", question = "Do you want to exit \the [src]?", yes_text = "Exit", no_text = "Stay", ask_flags = ASK_INSIDE, timeout = 0)
		else if(!hider())
			open_request(src, /datum/prompt/yes_no, PROC_REF(hide_answered), valid = PROC_REF(hide_valid), answerer = user, title = "Un-Hide?", question = "Do you want to hide in \the [src]?", yes_text = "Hide", no_text = "Stay", ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE, timeout = 0)
	else
		return HOOK_DECLINE

/// Re-checked: nobody else hid in the pile meanwhile.
/obj/structure/trash_pile/proc/hide_valid(datum/request/R)
	return !hider()

/obj/structure/trash_pile/proc/exit_answered(datum/act/request/A)
	if(!A.answer || !A.answer.value)
		return
	var/mob/living/L = A.request.answerer
	if(L == hider())
		rel_clear(src, nameof(hider))
	L.forceMove(get_turf(src))

/obj/structure/trash_pile/proc/hide_answered(datum/act/request/A)
	if(!A.answer || !A.answer.value)
		return
	var/mob/living/L = A.request.answerer
	L.forceMove(src)
	rel_set(src, nameof(hider), L)

/// Old attack_ghost: offer to spawn as a mouse. Never fell through to the default.
/obj/structure/trash_pile/proc/trash_pile_ghost_mouse(mob/observer/user, obj/item/held, datum/interaction/interaction)
	if(CONFIG_GET(flag/disable_player_mice))
		to_chat(user, span_warning("Spawning as a mouse is currently disabled."))
		return TRUE

	if(jobban_isbanned(user, JOB_GHOSTROLES))
		to_chat(user, span_warning("You cannot become a mouse because you are banned from playing ghost roles."))
		return TRUE

	if(!user.MayRespawn(TRUE))
		return TRUE

	var/turf/T = get_turf(src)
	if(!T || (T.z in using_map.admin_levels))
		to_chat(user, span_warning("You may not spawn as a mouse on this Z-level."))
		return TRUE

	var/timedifference = world.time - user.client.time_died_as_mouse
	if(user.client.time_died_as_mouse && timedifference <= CONFIG_GET(number/mouse_respawn_time) MINUTES)
		var/timedifference_text
		timedifference_text = time2text(CONFIG_GET(number/mouse_respawn_time) MINUTES - timedifference,"mm:ss")
		to_chat(user, span_warning("You may only spawn again as a mouse more than [CONFIG_GET(number/mouse_respawn_time)] minutes after your death. You have [timedifference_text] left."))
		return TRUE

	open_request(src, /datum/prompt/yes_no, PROC_REF(mouse_confirmed), valid = PROC_REF(mouse_valid), answerer = user, title = "Are you sure you want to squeek?", question = "Are you -sure- you want to become a mouse?", timeout = 0)
	return TRUE

/// Re-checked: still a ghost with a client.
/obj/structure/trash_pile/proc/mouse_valid(datum/request/R)
	var/mob/M = R.answerer
	return istype(M) && M.client && isobserver(M)

/obj/structure/trash_pile/proc/mouse_confirmed(datum/act/request/A)
	if(!A.answer || !A.answer.value)
		return
	var/mob/observer/user = A.request.answerer

	var/mob/living/simple_mob/animal/passive/mouse/host
	host = new /mob/living/simple_mob/animal/passive/mouse(get_turf(src))

	if(host)
		if(CONFIG_GET(flag/uneducated_mice))
			host.universal_understand = 0
		announce_ghost_joinleave(src, 0, "They are now a mouse.")
		host.ckey = user.ckey
		to_chat(host, span_info("You are now a mouse. Try to avoid interaction with players, and do not give hints away that you are more than a simple rodent."))

	var/atom/holder = get_holder_at_turf_level(src)
	holder.visible_message("[host] crawls out of \the [src].")
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

		act_message(H, user, MSG_SELF(span_notice("You search through \the [src].")), MSG_OTHERS("%T% searches through \the [src]."))
		if(hider())
			to_chat(hider(),span_warning("[user] is searching the trash pile you're in!"))

		//Do the searching
		om_task_timed(user, rand(4 SECONDS,6 SECONDS), target = src, receiver = src, on_done = PROC_REF(attack_hand_timed_done), done_args = list(user), claims = TRUE)
	return TRUE

/obj/structure/trash_pile/proc/attack_hand_timed_done(mob/user)
	if(hider() && prob(50))
		//If there was a hider, chance to reveal them
		to_chat(hider(),span_danger("You've been discovered!"))
		hider().forceMove(get_turf(src))
		rel_clear(src, nameof(hider))
		to_chat(user,span_danger("Some sort of creature leaps out of \the [src]!"))
	else
		loot_search(src, user, searchedby, 5)

/obj/structure/mob_spawner/mouse_nest
	name = "trash"
	desc = "A small heap of trash, perfect for mice and other pests to nest in."
	icon = 'icons/obj/trash_piles.dmi'
	icon_state = "randompile"
	simultaneous_spawns = 1
	destructible = 1
	spawn_delay = 1 HOUR

TYPE_TABLE(/obj/structure/mob_spawner/mouse_nest, mob_spawner_types, list( \
	/mob/living/simple_mob/animal/passive/mouse= 100, \
	/mob/living/simple_mob/animal/passive/cockroach = 25))

/obj/structure/mob_spawner/mouse_nest/Initialize(mapload)
	. = ..()
	COOLDOWN_START(src, spawn_cooldown, rand(0, spawn_delay))
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
	COOLDOWN_START(src, spawn_cooldown, rand(0, spawn_delay))

/// Relation view: hider (reads null once it is gone).
/obj/structure/trash_pile/proc/hider() as /mob/living
	return hider
