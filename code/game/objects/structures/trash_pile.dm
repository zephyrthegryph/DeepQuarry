/obj/structure/trash_pile
	name = "trash pile"
	desc = "A heap of garbage, but maybe there's something interesting inside?"
	icon = 'icons/obj/trash_piles.dmi'
	icon_state = "randompile"
	density = TRUE
	anchored = TRUE

	var/mob/living/hider		// A simple animal that might be hiding in the pile
	var/obj/structure/mob_spawner/mouse_nest/mouse_nest = null

CAPABILITIES(/obj/structure/trash_pile)
	extend(/datum/act/hit/generic, instead(then(PROC_REF(smashed_by))))
	climb()
	owns_one(nameof(mouse_nest), starts = /obj/structure/mob_spawner/mouse_nest)
	// the old attack_ghost: offer to spawn as a mouse (refused with the old reasons; never fell through to the default)
	op("become_mouse", observer(), label("Become mouse"), needs(req(PROC_REF(mouse_allowed), because = PROC_REF(mouse_refusal))),
		asks(/datum/prompt/yes_no, fields = list("title" = "Are you sure you want to squeek?", "question" = "Are you -sure- you want to become a mouse?", "timeout" = 0), keeps = TARGET_PRESENT),
		then(PROC_REF(mouse_confirmed)))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))
	op("search", hand(), label("Search"), claims(), needs(req(/mob/living/carbon/human, of = ON_ACTOR, silent = TRUE)), needs(req_loot_unsearched(), req_loot_not_picked_clean()), begins(PROC_REF(search_begins)), wait(PROC_REF(search_time)), loot_rolls(unless = PROC_REF(hider_leaps_out)))
	rolls(nameof(icon_state), PROC_REF(roll_icon_state))
	loot_search(table = /loot/trash_pile, wake_chance = 5)

/// Rolled before init (rolls()): what the pile looks like.
/obj/structure/trash_pile/proc/roll_icon_state(datum/roller/R)
	return R.choose(list("pile1", "pile2", "pilechair", "piletable", "pilevending", "brtrashpile", "microwavepile", "rackpile", "boxfort", "trashbag", "brokecomp"))

/// Old attackby: dropping gamma loot into the pile restores it.
/obj/structure/trash_pile/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	var/w_type = W.type
	if(w_type in GLOB.allocated_gamma_loot)
		to_chat(user,span_notice("You feel 	he [W] slip from your hand, and disappear into the trash pile."))
		user.unEquip(W)
		W.forceMove(src)
		restore_gamma_loot(w_type)
		consume(W, user)
	return OP_OK

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

/// A ghost may become a mouse here: player mice allowed, not banned, free to respawn, off the admin levels, past the mouse respawn time.
/obj/structure/trash_pile/proc/mouse_allowed(datum/act/op/A)
	return isnull(mouse_refusal(A))

/// Why a ghost may not become a mouse here, or null.
/obj/structure/trash_pile/proc/mouse_refusal(datum/act/op/A)
	return read_once(mouse_spawn_refusal(A.actor, get_turf(src))) // the config, the bans and the death time are asked when the click is made

/// Why `user` may not spawn as a mouse at `T`, or null: the config, the ghost-role ban, respawn rules, the admin levels and the mouse respawn time.
/// None of it is round state an op could watch (config, bans, a client's death time): it reads nothing the graph follows, and a requirement calls it inside read_once().
/proc/mouse_spawn_refusal(mob/observer/user, turf/T)
	READS_FROM()
	if(CONFIG_GET(flag/disable_player_mice))
		return "Spawning as a mouse is currently disabled."
	if(jobban_isbanned(user, JOB_GHOSTROLES))
		return "You cannot become a mouse because you are banned from playing ghost roles."
	if(!user.MayRespawn(FALSE))
		return MSG(trash_pile/may_not_respawn)
	if(!T || (T.z in using_map.admin_levels))
		return "You may not spawn as a mouse on this Z-level."
	var/died_at = user.client?.time_died_as_mouse
	var/timedifference = world.time - died_at
	if(died_at && timedifference <= CONFIG_GET(number/mouse_respawn_time) MINUTES)
		return "You may only spawn again as a mouse more than [CONFIG_GET(number/mouse_respawn_time)] minutes after your death. You have [time2text(CONFIG_GET(number/mouse_respawn_time) MINUTES - timedifference, "mm:ss")] left."
	return null

MSG_DEF_SELF(trash_pile/may_not_respawn, "You may not respawn now.")

/obj/structure/trash_pile/proc/mouse_confirmed(datum/act/op/A)
	var/datum/prompt/R = A.answer
	var/mob/observer/user = A.actor
	if(!R?.value || !user.client || !isobserver(user))
		return OP_OK

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

MSG_DEF(trash_pile/searching, "You search through %T%.", "%U% searches through %T%.")

/// The start of a search: whoever hides in the pile is warned, and the searcher says so.
/obj/structure/trash_pile/proc/search_begins(datum/act/op/A)
	if(hider())
		to_chat(hider(), span_warning("[A.actor] is searching the trash pile you're in!"))
	return /datum/msg/trash_pile/searching

/// How long a search takes, drawn when it starts.
/obj/structure/trash_pile/proc/search_time(datum/act/op/A)
	return rand(4 SECONDS, 6 SECONDS)

/// Whoever hides in the pile may leap out instead of the search yielding anything: TRUE when it did (the search ends there, nothing is rolled).
/obj/structure/trash_pile/proc/hider_leaps_out(datum/act/op/A)
	var/mob/user = A.actor
	if(!(hider() && prob(50)))
		return FALSE
	//If there was a hider, chance to reveal them
	to_chat(hider(),span_danger("You've been discovered!"))
	hider().forceMove(get_turf(src))
	rel_clear(src, nameof(hider))
	to_chat(user,span_danger("Some sort of creature leaps out of 	he [src]!"))
	return TRUE

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
