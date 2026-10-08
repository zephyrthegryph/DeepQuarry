// tgui-migration (commit 3ec748264e). browse()/datum/browser/admin_log_show panels migrated to TGUI; stale shims (show_browser macro, browse callsites) removed.
// Bracketed at file-header rather than per-hunk because the
// edits are mechanical and span the whole file; the commit SHA
// is the source of truth for per-line diff context.

//I'm sorry for this file, no one should have to deal with this
//I am in a pain trance and coding is the only thing that can distract me
//I am a dwarf in a fey mood, but what I make will not be a masterwork, woe

/datum/category_item/catalogue/fauna/stardog
	name = "Alien Wildlife - Star Dog"
	desc = "I appears to be a canine of some sort, though absolutely massive in scale and surrounded in radical redspace energies!"
	value = CATALOGUER_REWARD_SUPERHARD

/mob/living/simple_mob/vore/overmap/stardog
	name = "dog"
	desc = "It is a relatively ordinary looking canine mutt! It radiates mischief and otherworldly energy..."
	tt_desc = "E Canis lupus stellarus"

	scanner_desc = "I appears to be a canine of some sort, though absolutely massive in scale and surrounded in radical redspace energies!"
	catalogue_data = list(/datum/category_item/catalogue/fauna/stardog)

	icon = 'icons/mob/vore.dmi'
	icon_state = "woof"
	icon_living = "woof"
	icon_dead = "woof_dead"
	icon_rest = "woof_rest"

	om_child_type = /obj/effect/overmap/visitable/ship/simplemob/stardog

	response_help = "pets"
	response_disarm = "rudely paps"
	response_harm = "punches"

	attacktext = list("nipped", "chomped", "bullied", "gnaws on")
	attack_sound = SFX_VOICE_BORK
	friendly = list("snoofs", "nuzzles", "ruffs happily at", "smooshes on")

	has_langs = list(LANGUAGE_ANIMAL, LANGUAGE_CANILUNZT, LANGUAGE_GALCOM)
	say_list_type = /datum/say_list/softdog
	swallowTime = 0.1 SECONDS

	loot_list = list(/obj/random/underdark/uncertain)

	armor_spec = "melee=1000;bullet=1000;laser=1000;energy=1000;bomb=1000;bio=1000;rad=1000"

	movement_cooldown = 5
	copy_prefs_to_mob = FALSE
	player_msg = "The dog accepts you into itself, allowing you to dictate what will happen. The dog occasionally thinks unknowable thoughts, though you can understand some of its needs and desires. The dog shares its experience with you. You can navigate space, 'transition' to certain locations, and you can dine upon some of the space weather. The dog doesn't seem to know how any of this works exactly, this is just how things are for the dog, they come as naturally to the dog as blinking."

	var/affinity = 0
	var/obj/structure/control_pod/control_node = null
	var/admin_override = FALSE	//If true, makes affinity and nutrition irrelevant.
	// ALLOW(instance_list): d: per-mob weather_areas, sized at creation and filled in place; mobs are few
	var/list/weather_areas = list()	//We'll call a proc on these areas when we eat, don't worry!

CAPABILITIES(/mob/living/simple_mob/vore/overmap/stardog)
	verb_entry(/mob/living/simple_mob/proc/set_name, hidden = TRUE)
	verb_entry(/mob/living/simple_mob/proc/set_desc, hidden = TRUE)
	op("fur_pick", hand(), ungated(), label("Use"), when(req(PROC_REF(fur_pick_possible))), begins(MSG(stardog/fur_look)), asks(/datum/prompt/choice/stardog_fur_pick, fields = list("choices" = computed(PROC_REF(fur_pick_choices))), step = "pick"), then(PROC_REF(fur_pick_chosen)))

/mob/living/simple_mob/vore/overmap/stardog/proc/fur_pick_done(mob/living/user, mob/living/that_one)
	if(!istype(that_one.loc,/turf/simulated/floor/outdoors/fur))
		to_chat(user, span_warning("\The [that_one] got away..."))
		to_chat(that_one, span_notice("You got away!"))
		return
	var/prev_size = that_one.size_multiplier
	that_one.resize(RESIZE_TINY, ignore_prefs = TRUE)
	if(!that_one.attempt_to_scoop(user, ignore_size = TRUE, stance = (user.combat_mode ? I_HURT : I_HELP)))
		that_one.resize(prev_size, ignore_prefs = TRUE)
		return

MSG_DEF(stardog/fur_look, span_notice("You look through %T%'s fur..."), span_warning("%U% reaches for something in %T%'s fur..."))

/// Old attack_hand: pick someone out of the fur. Offered while there is someone to pick (the target list is the asks() step's choices).
/mob/living/simple_mob/vore/overmap/stardog/proc/fur_pick_possible(datum/act/op/A)
	var/mob/living/user = A.actor
	return read_once(istype(user) && user.pickup_pref && user.pickup_active && length(fur_pick_targets())) // preferences and who stands in the fur are asked when the click is made

/// The players standing in the fur who may be picked up.
/mob/living/simple_mob/vore/overmap/stardog/proc/fur_pick_targets()
	var/list/possible_targets = list()
	for(var/mob/living/player in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(!(player.z in child_om_marker.map_z))
			continue
		if(!(isliving(player) && istype(player.loc,/turf/simulated/floor/outdoors/fur) && player.client))
			continue
		if(player.resizable && player.pickup_pref)
			possible_targets |= player
	return possible_targets

/mob/living/simple_mob/vore/overmap/stardog/proc/fur_pick_choices(datum/act/A)
	return fur_pick_targets()

/// Re-checked on the answer: next to the stardog and able, and the one picked is still in its fur.
/datum/prompt/choice/stardog_fur_pick
	timeout = 0
	title = "Select a mob to grab!"
	question = "Select a mob:"
	ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE

/datum/prompt/choice/stardog_fur_pick/recheck_extra()
	var/reason = ..()
	if(reason)
		return reason
	var/mob/living/that_one = value
	if(QDELETED(that_one))
		return "gone"
	return istype(that_one.loc, /turf/simulated/floor/outdoors/fur) ? null : "not in the fur"

/mob/living/simple_mob/vore/overmap/stardog/proc/fur_pick_chosen(datum/act/op/A)
	var/mob/living/user = A.actor
	var/mob/living/that_one = A.step_value("pick")
	if(!istype(that_one))
		return OP_OK
	to_chat(that_one, span_danger("\The [user]'s hand reaches toward you!!!"))
	task_timed(user, 3 SECONDS, target = src, receiver = src, on_done = PROC_REF(fur_pick_done), done_args = list(user, that_one))
	return OP_OK

/mob/living/simple_mob/vore/overmap/stardog/life_type_post_due()
	return TRUE

/mob/living/simple_mob/vore/overmap/stardog/life_type_post(datum/seq_frame/life/F)
	..()
	if(src.admin_override)
		src.affinity = 9999
		src.set_nutrition(9999)
	if(src.devourable)	//This will cause problems probably so please do not eat the dog
		src.devourable = FALSE
		src.digestable = FALSE
	if(src.ckey && src.control_node)
		if(src.nutrition <= 200)
			src.adjust_affinity(-10)
		else if(src.nutrition < 500)
			src.adjust_affinity(-3)
		else
			src.adjust_affinity(-1)
		if(!src.affinity)
			src.control_node.eject()
	if(!src.ckey && src.resting)
		src.lay_down()

	if(istype(src.loc, /turf/unsimulated/map))
		if(!src.invisibility)
			src.invisibility = INVISIBILITY_ABSTRACT
			src.child_om_marker.invisibility = INVISIBILITY_NONE
			//legacy ai_holder wander tuning removed.
			src.melee_damage_lower = 50
			src.melee_damage_upper = 100
			src.mob_size = MOB_HUGE
			src.child_om_marker.set_light(5, 1, "#ff8df5")
			src.movement_cooldown = 5

	else if(src.invisibility)
		src.invisibility = INVISIBILITY_NONE
		src.child_om_marker.invisibility = INVISIBILITY_ABSTRACT
		//legacy ai_holder wander tuning removed.
		src.melee_damage_lower = 1
		src.melee_damage_upper = 5
		src.mob_size = MOB_SMALL
		src.child_om_marker.set_light(0)
		src.movement_cooldown = 0

/mob/living/simple_mob/vore/overmap/stardog/perform_the_nom(mob/living/user, mob/living/prey, mob/living/pred, obj/belly/belly, delay_time)
	to_chat(src, span_warning("You can't do that."))	//The dog can move back and forth between the overmap.
	return															//If it can do normal vore mechanics, it can carry players to the OM,
																	//and release them there. I think that's probably a bad idea.

/mob/living/simple_mob/vore/overmap/stardog/begin_instant_nom(mob/living/user, mob/living/prey, mob/living/pred, obj/belly/belly)
	to_chat(src, span_warning("You can't do that."))
	return

/mob/living/simple_mob/vore/overmap/stardog/Initialize(mapload)
	. = ..()
	child_om_marker?.set_light(5, 1, "#ff8df5")

/mob/living/simple_mob/vore/overmap/stardog/relations()
	. = ..()
	. += rel_one(nameof(control_node), back = nameof(/obj/structure/control_pod::host))

/mob/living/simple_mob/vore/overmap/stardog/get_status_tab_items()
	. = ..()
	. += ""
	. += "Affinity: [round(affinity)]"

/mob/living/simple_mob/vore/overmap/stardog/start_pulling(atom/movable/AM)
	if(!istype(loc, /turf/unsimulated/map))	//Don't pull stuff on the overmap
		..()

/mob/living/simple_mob/vore/overmap/stardog/proc/adjust_affinity(amount)
	if(amount > 0)
		var/multiplier = nutrition / 250
		affinity += (amount * multiplier)
	if(amount < 0)
		affinity += amount
	if(affinity <= 0)
		affinity = 0
	if(affinity > 1000)
		affinity = 1000

/mob/living/simple_mob/vore/overmap/stardog/verb/eject()
	set name = "Eject"
	set desc = "Stop controlling the dog and return to your own body."
	set category = VERB_CAT_ABILITIES_STARDOG

	control_node.eject()

/mob/living/simple_mob/vore/overmap/stardog/verb/eat_space_weather()
	set name = "Eat Space Weather"
	set desc = "Eat carp or rocks!"
	set category = VERB_CAT_ABILITIES_STARDOG

	var/obj/effect/overmap/event/E
	var/nut = 0
	var/aff = 0
	var/mob = FALSE
	var/ore = 0
	var/tre = 0
	var/msg = "REPLACE ME"
	var/heal = FALSE
	var/delet = TRUE

	for(var/obj/effect/overmap/event/e in contents_of(loc))
		if(istype(e, /obj/effect/overmap/event/carp))
			E = e
			nut = 250
			aff = -50
			mob = TRUE
			var/list/msglist = list(
				"You lap up \the [E]. They're pretty filling, but you don't really like the taste...",
				"You lap up \the [E]. You can feel them wiggle all the way down... They don't taste very good, but you feel energized afterward.",
				"You lap up \the [E]. They flee away from you, attempting to scatter in all directions, but you're faster! They leave an unpleasant taste on your tongue, but your belly doesn't seem to mind them."
			)
			msg = pick(msglist)
		else if(istype(e, /obj/effect/overmap/event/dust))
			E = e
			aff = -100
			tre = 15
			ore = 25
			var/list/msglist = list(
				"You lap up \the [E]. The dust clings to your mouth and throat!!! You cough and splutter unhappily! It is literally space dirt, and it tastes like it!",
				"You lap up \the [E]. The bitter taste of the dust sticks to your tongue and takes a lot of work to get off! It's really frustrating!",
				"You lap up \the [E]. Not only does it taste horrible and feel worse going down, some of it gets in your eyes!"
			)
			msg = pick(msglist)
		else if(istype(e, /obj/effect/overmap/event/meteor))
			E = e
			aff = -200
			tre = 5
			ore = 100
			var/list/msglist = list(
				"You lap up \the [E]. The rocks roll down your gullet haphazardly. Some of them knock together and clatter their way down, while others turn to powder. Some of them even have some pretty sharp edges that don't feel very nice! They certainly don't taste very nice, and they weight heavily inside of your belly...",
				"You lap up \the [E]. When they land inside you can feel the weight of them settle in. They make your insides kind of queasy...",
				"You lap up \the [E]. They taste like rocks, and make you think of all the better things you could be eating..."
			)

			msg = pick(msglist)
		else if(istype(e, /obj/effect/overmap/event/electric))
			E = e
			aff = 15
			msg = "You try to eat \the [E], but you find that no matter how much of it you lick or homn upon, yet more remains! It makes your mouth tingle, and your fur stand on end! It's kind of fun, but it doesn't taste like anything, and you definitely don't feel any more full."
			delet = FALSE
		else if(istype(e, /obj/effect/overmap/event/ion))
			E = e
			aff = 20
			msg = "When you approach \the [E], you find that the dog's will pulls away from your own a little bit. It seems to really like the shimmering clouds, and it feels really good to nestle up among them. Like taking a relaxing dip into a regenerative spring. Any aches and pains that the dog was experiencing seem to fade away, leaving it feeling refreshed!"
			heal = TRUE
			delet = FALSE
		else
			to_chat(src, span_warning("You can't eat \the [e]."))
			return

	if(!E)
		to_chat(src, span_warning("There isn't anything to eat here."))
		return

	to_chat(src, span_notice("You begin to eat \the [E]..."))

	task_start(/datum/task/timed/stardog_eat_space_weather_stardog, src, E, nut = nut, aff = aff, mob = mob, ore = ore, tre = tre, msg = msg, heal = heal, delet = delet)
	return TRUE

/datum/task/timed/stardog_eat_space_weather_stardog
	duration = 20 SECONDS
	complete_proc = /mob/living/simple_mob/vore/overmap/stardog/proc/eat_space_weather_stardog_done
	var/nut
	var/aff
	var/mob
	var/ore
	var/tre
	var/msg
	var/heal
	var/delet

/mob/living/simple_mob/vore/overmap/stardog/proc/eat_space_weather_stardog_done(datum/task/timed/stardog_eat_space_weather_stardog/task)
	var/obj/effect/overmap/event/E = task.target
	var/nut = task.nut
	var/aff = task.aff
	var/mob = task.mob
	var/ore = task.ore
	var/tre = task.tre
	var/msg = task.msg
	var/heal = task.heal
	var/delet = task.delet
	to_chat(src, span_notice("[msg]"))
	if(nut || aff)
		adjust_nutrition(nut)
		adjust_affinity(aff)
	if(mob)
		spawn_mob()
		to_chat(src, span_notice("You can feel something moving inside of you..."))
	if(ore)
		spawn_ore(ore)
	if(tre)
		spawn_treasure(tre)
	if(heal)
		fully_heal()
	if(delet)
		consumed(E)

/mob/living/simple_mob/vore/overmap/stardog/proc/spawn_mob()
	for(var/area/redgate/stardog/flesh_abyss/a in weather_areas)
		if(istype(a, /area/redgate/stardog/flesh_abyss))
			a.spawn_mob()
/mob/living/simple_mob/vore/overmap/stardog/proc/spawn_ore(chance)
	for(var/area/redgate/stardog/flesh_abyss/a in weather_areas)
		if(istype(a, /area/redgate/stardog/flesh_abyss) && prob(chance))
			a.spawn_ore()
/mob/living/simple_mob/vore/overmap/stardog/proc/spawn_treasure(chance)
	for(var/area/redgate/stardog/flesh_abyss/a in weather_areas)
		if(istype(a, /area/redgate/stardog/flesh_abyss) && prob(chance))
			a.spawn_treasure()

/mob/living/simple_mob/vore/overmap/stardog/proc/transition_down_done(atom/our_dest)
	act_message(src, null, null, MSG_OTHERS(span_warning("%U% disappears!!!")))
	stop_pulling()
	forceMove(get_turf(our_dest))
	adjust_nutrition(-1000)
	act_message(src, null, null, MSG_OTHERS(span_warning("%U% steps into the area as if from nowhere!")))

/mob/living/simple_mob/vore/overmap/stardog/verb/transition()	//Don't ask how it works. I don't know. I didn't think about it. I just thought it would be cool.
	set name = "Transition"
	set desc = "Attempt to go to the location you have arrived at, or return to space!"
	set category = VERB_CAT_ABILITIES_STARDOG
	if(nutrition <= 500)
		to_chat(src, span_warning("You're too hungry..."))
		return
	if(istype(loc, /turf/unsimulated/map))
		var/list/destinations = list()
		var/list/our_maps = list()
		for(var/obj/effect/overmap/visitable/v in contents_of(loc))
			if(v == child_om_marker)
				continue
			if(!v.map_z.len)
				continue
			for(var/our_z in v.map_z)
				our_maps |= our_z
		if(!our_maps.len)
			to_chat(src, span_warning("There is nowhere nearby to go to! You need to get closer to somewhere you can transition to before you can transition."))
			return
		for(var/obj/effect/landmark/l in REGISTRY_MEMBERS(REGISTRY_LANDMARKS))
			if(l.z in our_maps)
				if(istype(l,/obj/effect/landmark/stardog))
					destinations |= l

		if(!destinations.len)
			to_chat(src, span_warning("There is nowhere nearby to land! You need to get closer to somewhere else that you can transition to before you can transition."))
			return
		open_request(src, /datum/prompt/choice/stardog_transition, PROC_REF(transition_destination_chosen), answerer = src, choices = destinations)

	else
		to_chat(src, span_notice("You begin to transition back to space, stay still..."))
		task_timed(src, 15 SECONDS, target = src, receiver = src, on_done = PROC_REF(transition_stardog_done), done_args = list(), on_fail = PROC_REF(transition_stardog_failed), fail_args = list())
		return

/// Where to land. A cancel (or the timeout) decides not to.
/datum/prompt/choice/stardog_transition
	title = "Transition"
	question = "Where would you like to try to go?"
	timeout = 15 SECONDS
	ask_flags = ASK_CONSCIOUS

/mob/living/simple_mob/vore/overmap/stardog/proc/transition_destination_chosen(datum/act/request/A)
	if(!A.answer)
		var/datum/request/R = A.request
		if((R.outcome == REQ_CANCELLED || R.outcome == REQ_TIMED_OUT) && isnull(R.value))
			to_chat(src, span_warning("You decide not to transition."))
		return
	var/obj/effect/overmap/visitable/our_dest = A.answer.value
	if(QDELETED(our_dest))
		return
	to_chat(src, span_notice("You begin to transition down to \the [our_dest], stay still..."))
	task_timed(src, 15 SECONDS, target = src, receiver = src, on_done = PROC_REF(transition_down_done), done_args = list(our_dest), on_fail = PROC_REF(transition_stardog_failed))

/mob/living/simple_mob/vore/overmap/stardog/proc/transition_stardog_done()

	act_message(src, null, null, MSG_OTHERS(span_warning("%U% disappears!!!")))
	stop_pulling()
	forceMove(get_turf(get_overmap_sector(z)))
	adjust_nutrition(-500)

/mob/living/simple_mob/vore/overmap/stardog/proc/transition_stardog_failed()
	to_chat(src, span_warning("You were interrupted."))
	return

/obj/effect/overmap/visitable/ship/simplemob/stardog
	icon = 'icons/obj/overmap.dmi'
	icon_state = "ship"
	skybox_icon = 'icons/skybox/anomaly.dmi'
	skybox_icon_state = "space_dog"
	skybox_pixel_x = 0
	skybox_pixel_y = 0
	glide_size = 2
	parent_mob_type = /mob/living/simple_mob/vore/overmap/stardog
	scanner_desc = "CONFIGURE ME"

/turf/simulated/floor/outdoors/fur
	name = "fur"
	desc = "Thick, silky fur!"
	icon = 'icons/turf/fur.dmi'
	icon_state = "fur0"
	edge_blending_priority = 4
	initial_flooring = /datum/decl/flooring/fur
	resistance_flags = BOMB_PROOF // it's a living hide: blasts don't tear it up
	var/tree_chance = 25
	var/tree_color = null
	var/tree_type = /obj/structure/flora/tree/fur

CAPABILITIES(/turf/simulated/floor/outdoors/fur)
	op("fur_item", item(/obj/item), label("Nothing"), passes(), then(PROC_REF(fur_item_passes)))
	op("fur_pet", hand(), ungated(), label("Pet"), then(PROC_REF(fur_pet)))
	op("fur_pet_verb", menu(), label("Pet Fur"), then(PROC_REF(fur_verb_pet)))
	op("fur_emote_beyond", menu(), label("Emote Beyond"), needs(req_adjacent(), req_capable(), req(PROC_REF(emoter_is_living), silent = TRUE), req(PROC_REF(emoter_not_muted), because = MSG(fur/ic_muted))), asks(/datum/prompt/text, fields = list("title" = "Emote Beyond", "question" = "Type a message to emote.", "encode" = FALSE, "timeout" = 0), step = "message"), then(PROC_REF(fur_verb_emote_beyond)))

MSG_DEF_SELF(fur/ic_muted, "you cannot speak in IC (muted)")

/// Old Emote Beyond verb: Emote to those beyond the fur!
/turf/simulated/floor/outdoors/fur/proc/emoter_is_living(datum/act/op/A)
	return isliving(A.actor)

/turf/simulated/floor/outdoors/fur/proc/emoter_not_muted(datum/act/op/A)
	return dq_actor_not_ic_muted(A.actor)

/// An item used on the fur does nothing to it: the click goes on (the old interaction_pass).
/turf/simulated/floor/outdoors/fur/proc/fur_item_passes(datum/act/op/A)
	return OP_PASS

/// Old attack_hand: the turf's own touch, then petting.
/turf/simulated/floor/outdoors/fur/proc/fur_pet(datum/act/op/A)
	var/mob/user = A.actor
	turf_hand(user, A.held, null)
	fur_verb_pet(A)
	return OP_OK

/turf/simulated/floor/outdoors/fur/Entered(atom/movable/AM, atom/oldloc)
	. = ..()
	if(ishuman(AM))
		var/mob/living/carbon/human/L = AM
		L.fur_submerge()

/turf/simulated/floor/outdoors/fur/Exited(atom/movable/AM, atom/new_loc)
	. = ..()
	if(ishuman(AM))
		var/mob/living/carbon/human/L = AM
		L.fur_submerge()

/mob/living/carbon/human/proc/fur_submerge()
	if(QDESTROYING(src))
		return

	remove_layer(MOB_WATER_LAYER)

	if(!istype(loc,/turf/simulated/floor/outdoors/fur) || lying)
		return

	var/atom/A = loc
	var/image/I = image(icon = 'icons/turf/fur.dmi', icon_state = "submerged", layer = BODY_LAYER+MOB_WATER_LAYER)
	I.color = A.color
	overlays_standing[MOB_WATER_LAYER] = I

	apply_layer(MOB_WATER_LAYER)

// ALLOW(init/INSTANCE_STATE): rolls whether a tree grows on this tile
/turf/simulated/floor/outdoors/fur/Initialize(mapload)
	. = ..()
	if(tree_chance && prob(tree_chance) && !check_density())
		var/obj/structure/flora/tree/tree = new tree_type(src)
		if(tree_color)
			tree.color = tree_color
		else
			tree.color = color

/// Old Pet Fur verb: Pet the fur!
/turf/simulated/floor/outdoors/fur/proc/fur_verb_pet(datum/act/op/A)
	var/mob/user = A.actor
	act_message(user, src, MSG_SELF(span_notice("You pet %T%.")), MSG_OTHERS(span_notice("%U% pets %T%.")), runemessage = "pet pat...")
	var/obj/effect/overmap/visitable/ship/simplemob/stardog/s = get_overmap_sector(z)

	if(s && istype(s, /obj/effect/overmap/visitable/ship/simplemob/stardog))
		var/mob/living/simple_mob/vore/overmap/stardog/m = s.parent
		m.adjust_affinity(1)
		if(m.affinity >= 10 && prob(5))
			act_message(m, null, null, MSG_OTHERS("%U%'s tail wags happily!"))

/// Requirement: the actor isn't muted from IC speech.
/proc/dq_actor_not_ic_muted(mob/actor, atom/target, obj/item/held)
	READS_FROM() // a player's mute preference is asked when the verb is chosen
	return !(actor?.client?.prefs?.muted & MUTE_IC)

/turf/simulated/floor/outdoors/fur/proc/fur_verb_emote_beyond(datum/act/op/A)
	var/mob/living/L = A.actor
	emote_beyond_entered(L, A.step_value("message"))
	return OP_OK

/turf/simulated/floor/outdoors/fur/proc/emote_beyond_entered(mob/living/L, message)
	message = sanitize_or_reflect(message,L)
	if (!message)
		return
	if (L.stat == DEAD)
		return L.say_dead(message)
	var/obj/effect/overmap/visitable/ship/simplemob/stardog/s = get_overmap_sector(z)
	if(!s || !istype(s, /obj/effect/overmap/visitable/ship/simplemob/stardog))
		return

	var/mob/living/simple_mob/vore/overmap/stardog/m = s.parent

	L.log_message("(SUBTLE) [message]", LOG_EMOTE)
	message = span_emote_subtle(span_bold("[L]") + " " + span_italics("[message]"))
	message = span_bold("(From the back of \the [m]) ") + message
	message = encode_html_emphasis(message)

	var/undisplayed_message = span_emote(span_bold("[L]") + " " + span_italics("does something too subtle for you to see."))
	var/list/vis = get_mobs_and_objs_in_view_fast(get_turf(m),1,2)
	var/list/vis_mobs = vis["mobs"]
	vis_mobs |= L
	for(var/mob/M as anything in vis_mobs)
		if(isnewplayer(M))
			continue
		if(isobserver(M) && (!M.client?.prefs?.read_preference(/datum/preference/toggle/ghost_see_whisubtle) || \
		!L.client?.prefs?.read_preference(/datum/preference/toggle/whisubtle_vis) && !check_rights_for(M.client, R_HOLDER)))
			M.show_message(undisplayed_message, 2)
		else
			M.show_message(message, 2)
			if(M.read_preference(/datum/preference/toggle/subtle_sounds))
				M << sound('sound/talksounds/subtle_sound.ogg', volume = 50)

/datum/decl/flooring/fur
	name = "fur"
	desc = "Thick, silky fur!"
	icon = 'icons/turf/fur.dmi'
	icon_base = "fur"
	has_base_range = 15

	can_paint = TRUE

/obj/structure/flora/tree/fur
	name = "tall fur"
	desc = "Tall stalks of fur block your path! Someone needs a trim!"
	icon = 'icons/obj/fur_tree.dmi'
	icon_state = "tallfur1"
	base_state = "tallfur"
	opacity = TRUE
	product = /obj/item/stack/material/fur
	product_amount = 10
	max_integrity = 100
	pixel_x = 0
	pixel_y = 0
	shake_animation_degrees = 2
	sticks = FALSE
	var/mob_chance = 5
	var/static/list/mob_list = list(	//Just, all the vore mobs. If some of the paths weren't shitty I would just put like `subtypesof(/mob/living/simple_mob/vore)` here. Maybe I'll fix that later, I am dying right now, I hope I will be remembered fondly when I die
		/mob/living/simple_mob/vore/aggressive/corrupthound,
		/mob/living/simple_mob/vore/aggressive/corrupthound/prettyboi,
		/mob/living/simple_mob/vore/aggressive/deathclaw,
		/mob/living/simple_mob/vore/aggressive/dino,
		/mob/living/simple_mob/vore/aggressive/dragon,
		/mob/living/simple_mob/vore/aggressive/frog,
		/mob/living/simple_mob/vore/aggressive/giant_snake,
		/mob/living/simple_mob/vore/aggressive/mimic,
		/mob/living/simple_mob/vore/aggressive/panther,
		/mob/living/simple_mob/vore/aggressive/rat,
		/mob/living/simple_mob/vore/alienanimals/catslug,
		/mob/living/simple_mob/vore/alienanimals/dustjumper,
		/mob/living/simple_mob/vore/alienanimals/skeleton,
		/mob/living/simple_mob/vore/alienanimals/space_jellyfish,
		/mob/living/simple_mob/vore/alienanimals/startreader,
		/mob/living/simple_mob/vore/alienanimals/succlet,
		/mob/living/simple_mob/vore/alienanimals/teppi,
		/mob/living/simple_mob/vore/alienanimals/teppi/baby,
		/mob/living/simple_mob/vore/bee,
		/mob/living/simple_mob/vore/bigdragon,
		/mob/living/simple_mob/vore/bigdragon/friendly,
		/mob/living/simple_mob/vore/catgirl,
		/mob/living/simple_mob/vore/fennec,
		/mob/living/simple_mob/vore/fennec/huge,
		/mob/living/simple_mob/vore/fennix,
		/mob/living/simple_mob/vore/greatwolf,
		/mob/living/simple_mob/vore/hippo,
		/mob/living/simple_mob/vore/horse,
		/mob/living/simple_mob/vore/horse/big,
		/mob/living/simple_mob/vore/jelly,
		/mob/living/simple_mob/vore/lamia/random,
		/mob/living/simple_mob/vore/leopardmander,
		/mob/living/simple_mob/vore/oregrub,
		/mob/living/simple_mob/vore/otie,
		/mob/living/simple_mob/vore/otie/red,
		/mob/living/simple_mob/vore/pakkun,
		/mob/living/simple_mob/vore/rabbit,
		/mob/living/simple_mob/vore/redpanda,
		/mob/living/simple_mob/vore/sect_drone,
		/mob/living/simple_mob/vore/sect_queen,
		/mob/living/simple_mob/vore/sheep,
		/mob/living/simple_mob/vore/solargrub,
		/mob/living/simple_mob/vore/squirrel,
		/mob/living/simple_mob/vore/squirrel/big,
		/mob/living/simple_mob/vore/weretiger,
		/mob/living/simple_mob/vore/wolf,
		/mob/living/simple_mob/vore/wolf/direwolf,
		/mob/living/simple_mob/vore/wolfgirl,
		/mob/living/simple_mob/vore/woof
	)

/obj/structure/flora/tree/fur/choose_icon_state()
	return "[base_state][rand(1, 2)]"

/// Overrides tree's interaction_search_sticks(): no sticks to find in fur.
/obj/structure/flora/tree/fur/interaction_search_sticks(datum/act/op/A)
	return OP_OK

/obj/structure/flora/tree/fur/die()
	if(product && product_amount)
		var/obj/item/stack/material/fur/F = new product(get_turf(src), product_amount)
		F.color = color
	visible_message(span_notice("\The [src] is felled!"))
	if(prob(mob_chance))
		if(!mob_list.len)
			return
		var/ourmob = pickweight(mob_list)
		var/mob/living/simple_mob/s = new ourmob(get_turf(src))
		visible_message(span_danger("\The [s] tumbles out of \the [src]!"))
		//legacy ai_holder.hostile/retaliate replaced with brain API.
		s.ai_brain?.set_hostile(FALSE)
		s.set_ghostjoin(TRUE)
		s.ghostjoin_icon()

	var/obj/effect/overmap/visitable/ship/simplemob/stardog/s = get_overmap_sector(z)
	if(s && istype(s,/obj/effect/overmap/visitable/ship/simplemob/stardog))
		var/mob/living/simple_mob/vore/overmap/stardog/dog = s.parent
		dog.adjust_affinity(15)

	destroyed(src)

/obj/structure/flora/tree/fur/wall
	name = "dense fur"
	desc = "Silky and soft, but too thick to pass or cut!"

CAPABILITIES(/obj/structure/flora/tree/fur/wall)
	op("fur_wall_item", item(/obj/item), passes(), priority(OP_PRIORITY_PART + 1), then(PROC_REF(fur_wall_item_passes)))

/// An item used on the dense fur does nothing to it: the click goes on (the old interaction_pass).
/obj/structure/flora/tree/fur/wall/proc/fur_wall_item_passes(datum/act/op/A)
	return OP_PASS

/area/redgate/stardog
	name = "dog"
/area/redgate/stardog/flesh_abyss
	name = "flesh abyss"
	icon_state = "redblatri"
	forced_ambience = list('sound/vore/stomach_loop.ogg', 'sound/vore/sunesound/prey/loop.ogg')
	floracountmax = 0
	valid_flora = list(
		/obj/structure/outcrop/coal = 10,
		/obj/structure/outcrop/diamond = 1,
		/obj/structure/outcrop/gold = 3,
		/obj/structure/outcrop/iron = 10,
		/obj/structure/outcrop/lead = 6,
		/obj/structure/outcrop/phoron = 10,
		/obj/structure/outcrop/platinum = 5,
		/obj/structure/outcrop/silver = 8,
		/obj/structure/outcrop/uranium = 3,
		/obj/random/outcrop = 5
	)

	semirandom = TRUE
	semirandom_groups = 1
	semirandom_group_min = 5
	semirandom_group_max = 15
	mob_intent = "retaliate"
	valid_mobs = list(
		list(
			/mob/living/simple_mob/vore/vore_hostile/abyss_lurker = 100,
			/mob/living/simple_mob/vore/vore_hostile/leaper = 100,
			/mob/living/simple_mob/vore/vore_hostile/gelatinous_cube = 10
			)
			)

	var/mob_chance = 10
	var/treasure_chance = 50
	var/static/list/valid_treasure = list(
		/obj/item/cell/infinite = 5,
		/obj/item/cell/device/weapon/recharge/alien = 5,
		/obj/item/nif/authentic = 1,
		/obj/item/toy/bosunwhistle = 50,
		/obj/random/mouseray = 50,
		/obj/item/gun/energy/mouseray/metamorphosis/advanced/random = 10,
		/obj/item/gun/energy/mouseray/metamorphosis/advanced = 5,
		/obj/item/clothing/mask/gas/voice = 25,
		/obj/item/perfect_tele = 15,
		/obj/item/gun/energy/sizegun = 50,
		/obj/item/slow_sizegun = 50,
		/obj/item/capture_crystal/master = 5,
		/obj/item/capture_crystal/ultra = 15,
		/obj/item/capture_crystal/great = 25,
		/obj/item/capture_crystal/random = 50,
		/obj/random/pizzabox = 10,	//The dog intercepted your pizza voucher delivery, what a scamp
		/obj/item/bluespace_harpoon = 15,
		/obj/random/awayloot = 5,
		/obj/random/cash = 15,
		/obj/random/cash/big = 10,
		/obj/random/cash/huge = 5,
		/obj/random/maintenance/clean = 10,
		/obj/random/maintenance/misc = 10
		)
	no_comms = TRUE
	ghostjoin = TRUE
	sound_env = SOUND_ENVIRONMENT_CAVE
	var/treasuremax = 3
	var/spawnstuff = TRUE
	var/include_enzyme = FALSE

/area/redgate/stardog/flesh_abyss/EvalValidSpawnTurfs()
	for(var/turf/simulated/floor/F in area_contents_of_type(src, /turf/simulated/floor))
		if(istype(F, /turf/simulated/floor/flesh))
			rel_add(src, nameof(valid_spawn_turfs), F)

		if(include_enzyme)
			if(istype(F, /turf/simulated/floor/water/digestive_enzymes))
				rel_add(src, nameof(valid_spawn_turfs), F)

/area/redgate/stardog/flesh_abyss/spawn_flora_on_turf()
	if(!spawnstuff)
		return
	if(!length(valid_flora))
		log_mapping("[src] does not have a set valid flora list!")
		return TRUE

	var/obj/F
	var/turf/Turf
	var/howmany = rand(0,floracountmax)
	for(var/floracount = 1 to howmany)
		F = pickweight(valid_flora || list())
		Turf = DEFAULTPICK(valid_spawn_turfs, null)
		if(!Turf.check_density())
			new F(Turf)

/area/redgate/stardog/flesh_abyss/spawn_mob_on_turf()
	if(!spawnstuff)
		return
	if(!length(valid_mobs))
		log_mapping("[src] does not have a set valid mobs list!")
		return TRUE

	var/mob/M
	var/turf/Turf
	if(semirandom)
		for(var/groupscount = 1 to (semirandom_groups))
			var/ourgroup = pickweight(valid_mobs || list())
			var/goodnum = rand(semirandom_group_min, semirandom_group_max)
			for(var/mobscount = 1 to (goodnum))
				M = pickweight(ourgroup)
				Turf = DEFAULTPICK(valid_spawn_turfs, null)
				if(!Turf.check_density())
					var/mob/ourmob = new M(Turf)
					adjust_mob(ourmob)
	else
		for(var/mobscount = 1 to mobcountmax)
			M = pickweight(valid_mobs || list())
			Turf = DEFAULTPICK(valid_spawn_turfs, null)
			if(!Turf.check_density())
				var/mob/ourmob = new M(Turf)
				adjust_mob(ourmob)

/area/redgate/stardog/flesh_abyss/proc/spawn_mob()
	if(!spawnstuff)
		return
	if(!length(valid_mobs))
		log_mapping("[src] does not have a set valid mobs list!")
		return

	if(!prob(mob_chance))
		return
	var/mob/M
	var/turf/Turf
	var/goodnum = rand(semirandom_group_min, semirandom_group_max)
	for(var/mobscount = 1 to goodnum)
		M = pickweight(pickweight(valid_mobs || list()))
		Turf = DEFAULTPICK(valid_spawn_turfs, null)
		if(!Turf.check_density())
			var/mob/ourmob = new M(Turf)
			adjust_mob(ourmob)

/area/redgate/stardog/flesh_abyss/proc/spawn_ore()
	if(!spawnstuff)
		return
	if(!length(valid_flora))
		log_mapping("[src] does not have a set valid flora list!")
		return

	var/obj/F
	var/turf/Turf
	var/howmany = rand(1,floracountmax)
	for(var/ore = 1 to howmany)
		F = pickweight(valid_flora || list())
		Turf = DEFAULTPICK(valid_spawn_turfs, null)
		if(!Turf.check_density())
			new F(Turf)

/area/redgate/stardog/flesh_abyss/proc/spawn_treasure()
	if(!spawnstuff)
		return
	if(treasure_chance <= 0)
		return
	if(!valid_treasure.len)
		log_mapping("[src] does not have a set valid treasure list!")
		return

	var/obj/F
	var/turf/Turf
	var/howmany = rand(1,treasuremax)
	for(var/treasure = 1 to howmany)
		if(prob(treasure_chance))
			continue
		F = pickweight(valid_treasure)
		Turf = DEFAULTPICK(valid_spawn_turfs, null)
		if(!Turf.check_density())
			new F(Turf)

/area/redgate/stardog/flesh_abyss/play_ambience(mob/living/L, initial = TRUE)
	if(!L.check_sound_preference(/datum/preference/toggle/digestion_noises))
		return
	..()

/obj/structure/control_pod	//god someone is going to try to fuck with this, everyone is going to be angry, I'm so sorry
	name = "node"
	desc = "A smooth node of nerves and flesh. It seems almost to radiate whispers of alien thought and emotion."
	icon = 'icons/obj/flesh_machines.dmi'
	icon_state = "control_node0"

	density = TRUE
	anchored = TRUE
	pixel_x = -16
	pixel_y = -10
	unacidable = TRUE

	var/mob/living/simple_mob/vore/overmap/stardog/host
	var/mob/living/controller

/obj/structure/control_pod/Initialize(mapload)
	. = ..()
	set_up()

/obj/structure/control_pod/proc/set_up()
	var/obj/effect/overmap/visitable/ship/simplemob/stardog/s = get_overmap_sector(z)
	if(istype(s,/obj/effect/overmap/visitable/ship/simplemob/stardog))
		var/mob/living/simple_mob/vore/overmap/stardog/dog = s.parent
		if(!dog.control_node)
			rel_set(src, nameof(host), dog)

/obj/structure/control_pod/relations()
	. = ..()
	. += rel_one(nameof(host), back = nameof(/mob/living/simple_mob/vore/overmap/stardog::control_node))

CAPABILITIES(/obj/structure/control_pod)
	op("hand", hand(), label("Use"), then(PROC_REF(interaction_hand)))

/// Old attack_hand.
/obj/structure/control_pod/proc/interaction_hand(datum/act/op/A)
	var/mob/living/user = A.actor
	if(!host)
		set_up()
		if(!host)
			to_chat(user, span_warning("It doesn't respond..."))
			return TRUE
	control(user)
	return TRUE

/obj/structure/control_pod/proc/control(mob/living/user)
	if(!host.affinity)	//take care of my dog
		to_chat(user, span_warning("As you press your hand to \the [src], it resists your advance... A sense of longing ripples through your mind..."))
		return
	if(controller)	//busy
		to_chat(user, span_warning("You can see \the [controller] inside! Tendrils of nerves seem to have attached themselves to \the [controller]! There's no room for you right now!"))
		return
	act_message(user, src, MSG_SELF(span_notice("You reach out to touch %T%...")), MSG_OTHERS(span_notice("%U% reaches out to touch %T%...")))
	task_timed(user, 10 SECONDS, target = src, receiver = src, on_done = PROC_REF(control_control_pod_done), done_args = list(user), on_fail = PROC_REF(control_control_pod_failed), fail_args = list(user))
	return TRUE

/obj/structure/control_pod/proc/control_control_pod_done(mob/living/user)
	if(controller)	//got busy while you were waiting, get rekt
		to_chat(user, span_warning("You can see \the [controller] inside! Tendrils of nerves seem to have attached themselves to \the [controller]! There's no room for you right now!"))
		return
	rel_set(src, nameof(controller), user)
	visible_message(span_warning("\The [src] accepts \the [controller], submerging them beneath the surface of the flesh!"))
	user.stop_pulling()
	user.forceMove(src)
	move_player(user, host, "took control of [host] through [src]", share = TRUE)
	log_admin("[host.ckey] has taken contol of \the [host].")
	icon_state = "control_node1"
	plane = ABOVE_MOB_PLANE
	set_light(5, 0.75, "#f94bff")

/obj/structure/control_pod/proc/control_control_pod_failed(mob/living/user)
	act_message(user, src, MSG_SELF(span_warning("You pull back from %T%.")), MSG_OTHERS(span_warning("%U% pulls back from %T%.")))
	return

/obj/structure/control_pod/proc/eject()
	to_chat(host, span_warning("You feel your control over \the [host] slip away from you!"))
	controller.forceMove(get_turf(src))
	move_player(host, controller, "ejected from [host] through [src]")
	visible_message(span_warning("\The [controller] is ejected from \the [src], tumbling free!"))
	log_admin("[controller.ckey] is no longer controlling [host], they have been returned to their body, [controller].")
	icon_state = "control_node0"
	plane = OBJ_PLANE
	set_light(0)
	var/our_x = rand(-5,5) + x
	var/our_y = rand(-5,5) + y

	var/turf/throwtarg = locate(our_x, our_y, z)	//teehee
	play_sfx(src, SFX_VORE_SCHLORP, volume_channel = VOLUME_CHANNEL_VORE)
	controller.throw_at(throwtarg, 10, 1)
	rel_clear(src, nameof(controller))

/obj/effect/landmark/stardog	//I didn't know how else to decide where the dog will land
	name = "stardog landing"
	icon = 'icons/obj/landmark_vr.dmi'
	icon_state = "transition"

// ALLOW(init/INSTANCE_STATE): names itself after the area it is placed in
/obj/effect/landmark/stardog/Initialize(mapload)
	. = ..()
	var/area/a = get_area(src)
	name = a.name

/obj/machinery/computer/ship/navigation/telescreen/dog_eye
	name = "visual nexus"
	desc = "A glowing bundle of nerves across which you can see what the dog sees."
	icon = 'icons/obj/flesh_machines.dmi'
	icon_state = "screen_eye"
	pixel_x = -16
	pixel_y = -16
	clicksound = SFX_VORE_SQUISH1

CAPABILITIES(/obj/machinery/computer/ship/navigation/telescreen/dog_eye)

/obj/machinery/computer/ship/navigation/telescreen/dog_eye/draw(datum/look/look)
	..()
	look.state("screen_eye")

MSG_DEF_SELF(ship_emote/too_far, "too far away")
MSG_DEF_SELF(ship_emote/incapable, "you can't do that right now")

/obj/machinery/computer/ship/navigation/proc/ship_emote_in_view(datum/act/op/A)
	// The host's current seven-tile view has no published visibility dependency; sample the real view at admission and resumption.
	return A.actor && read_once(get_dist(A.actor, src)) <= 7 && (src in read_once(view(7, A.actor)))

/obj/machinery/computer/ship/navigation/proc/ship_emoter_capable(datum/act/op/A)
	return dq_actor_can_act(A.actor, src, A.held)

/obj/machinery/computer/ship/navigation/proc/ship_emoter_not_muted(datum/act/op/A)
	return dq_actor_not_ic_muted(A.actor)

/// The old verb's `set src in oview(7)`.
/proc/dq_emote_beyond_in_view(mob/actor, atom/target, obj/item/held)
	return actor && target && get_dist(actor, target) <= 7 && (target in view(7, actor))

/obj/machinery/computer/ship/navigation/proc/emote_beyond_entered(datum/act/op/A)
	var/mob/living/L = A.actor
	var/message = sanitize_or_reflect(A.step_value("message"), L)
	if (!message)
		return
	if (L.stat == DEAD)
		return L.say_dead(message)
	var/obj/effect/overmap/visitable/ship/s = get_overmap_sector(z)
	if(!s || !istype(s, /obj/effect/overmap/visitable/ship))
		to_chat(L, span_warning("You can't do that here."))
		return

	L.log_message("(SUBTLE) [message]", LOG_EMOTE)
	message = span_emote_subtle(span_bold("[L]") + " " + span_italics("[message]"))
	message = span_bold("(From within \the [s]) ") + message
	message = encode_html_emphasis(message)

	var/undisplayed_message = span_emote(span_bold("[L]") + " " + span_italics("does something too subtle for you to see."))
	var/list/vis = get_mobs_and_objs_in_view_fast(get_turf(s),1,2)
	var/list/vis_mobs = vis["mobs"]
	vis_mobs |= L
	for(var/mob/M as anything in vis_mobs)
		if(isnewplayer(M))
			continue
		if(isobserver(M) && (!M.client?.prefs?.read_preference(/datum/preference/toggle/ghost_see_whisubtle) || \
		!L.client?.prefs?.read_preference(/datum/preference/toggle/whisubtle_vis) && !check_rights_for(M.client, R_HOLDER)))
			M.show_message(undisplayed_message, 2)
		else
			M.show_message(message, 2)
			if(M.read_preference(/datum/preference/toggle/subtle_sounds))
				M << sound('sound/talksounds/subtle_sound.ogg', volume = 50)

/area/redgate/stardog/eyes

	name = "eye"
	icon_state = "bluwhicir"

	var/list/our_eyes

/area/redgate/stardog/eyes/Entered(mob/M)
	. = ..()
	consider_eyes()

/area/redgate/stardog/eyes/Exited(atom/movable/AM, newLoc)
	. = ..()
	consider_eyes()

/area/redgate/stardog/eyes/proc/consider_eyes()	//CONSIDER THEM PLEASE
	var/close = FALSE
	var/list/check = get_area_turfs(/area/redgate/stardog/eyes)
	for(var/turf/t in check)
		for(var/thing in contents_of(t))
			if(istype(thing, /obj/effect/dog_eye))	//We can have eyes in our eyes, it's fine
				continue
			if(isobserver(thing))	//Ghosts aren't real
				continue
			if(isobj(thing) || ismob(thing))
				close = TRUE	//AAAAAAAAAAAAAAAUUUUUUUUGHHHHHHHHH ITS IN MY EYES HELP

	for(var/obj/effect/dog_eye/e in our_eyes)
		if(close)
			e.icon_state = "eye_closed"	// u . u
		else
			e.icon_state = "eye_open"	// * w *

/obj/effect/dog_eye
	name = "eye"
	desc = "It's peeking!"
	icon = 'icons/obj/flesh_machines.dmi'
	icon_state = "eye_open"
	anchored = TRUE

	pixel_x = -16

/obj/effect/dog_nose
	name = "nose"
	desc = "Good for sniffin' with!"
	icon = 'icons/obj/flesh_machines.dmi'
	icon_state = "nose"
	anchored = TRUE

CAPABILITIES(/obj/effect/dog_nose)
	op("boop_snoot", hand(), label("Boop"), then(PROC_REF(interaction_boop_snoot)))

/// Old attack_hand.
/obj/effect/dog_nose/proc/interaction_boop_snoot(datum/act/op/A)
	var/mob/living/user = A.actor
	act_message(user, src, MSG_SELF(span_notice("You boop the snoot.")), MSG_OTHERS(span_notice("%U% boops the snoot.")), runemessage = "boop")
	return TRUE

/obj/effect/dog_nose/Crossed(atom/movable/AM as mob|obj)
	. = ..()
	sneef(AM)

/obj/effect/dog_nose/proc/sneef(mob/living/L)
	if(!isliving(L))
		return
	if(L.client)
		to_chat(L, span_notice("A hot breath rushes up from under your feet, before the air rushes back down into the dog's nose as the dog sniffs you! SNEEF SNEEF!!!"))

/obj/effect/dog_eye/Initialize(mapload)
	. = ..()
	var/area/redgate/stardog/eyes/e = get_area(src)
	if(istype(e,/area/redgate/stardog/eyes))
		rel_add(e, nameof(e.our_eyes), src)

/obj/effect/dog_teleporter	//look, I could have just used a bump teleporter, and I don't have an excuse, also everyone is going to be angry but it hurts too much for me to care right now, hopefully I will finish this before I start caring
	name = "mouth"
	desc = "It's waiting to accept treats!"
	icon = 'icons/obj/flesh_machines.dmi'
	icon_state = "mouth"
	invisibility = INVISIBILITY_NONE
	anchored = TRUE
	pixel_x = -16
	var/id = "mouth_a"							//same id will be linked
	var/static/list/dog_teleporters = list()	//List of all the teleporters
	var/reciever = FALSE						//If true, doesn't teleport, only recieves
	var/obj/effect/dog_teleporter/target		//Target for teleporting to, automatically set by id
	var/throw_through = TRUE					//When moved the mob/obj will be thrown south
	var/teleport_sound = SFX_VORE_SCHLORP	//The sound that plays when we use the teleporter. Respects vore sound preferences.
	var/teleport_message = ""
	var/check_keys = FALSE
	var/check_prefs = TRUE

/obj/effect/dog_teleporter/Initialize(mapload)
	. = ..()
	rel_add(src, nameof(dog_teleporters), src)
	do_setup()
	if(icon_state == "exit_b")	//♪♫Blinded by the light♪♫
		set_light(5, 1, "#ffffff")

/obj/effect/dog_teleporter/proc/do_setup()
	if(target)
		return
	for(var/obj/effect/dog_teleporter/T in dog_teleporters.Copy())
		if(!istype(T,/obj/effect/dog_teleporter))
			rel_remove(src, nameof(dog_teleporters), T)
			continue
		if(id == T.id)
			if(T == src)
				continue
			rel_set(src, nameof(target), T)
			if(!T.target)
				rel_set(T, nameof(T.target), src)

/obj/effect/dog_teleporter/Crossed(atom/movable/AM as mob|obj)	//I am ashamed to admit how long it took to get this to do anything
	. = ..()
	lets_go(AM)

CAPABILITIES(/obj/effect/dog_teleporter)
	op("dog_teleport", hand(), then(PROC_REF(interaction_dog_teleport)))

/// Old attack_hand: touching it sends you through.
/obj/effect/dog_teleporter/proc/interaction_dog_teleport(datum/act/op/A)
	var/mob/living/user = A.actor
	lets_go(user)
	return TRUE

/obj/effect/dog_teleporter/attack_generic(mob/user)
	. = ..()
	lets_go(user)

/obj/effect/dog_teleporter/proc/lets_go(atom/movable/AM as mob|obj)	//Wahoo! Here we go!
	if(reciever)
		return
	if(!target)
		do_setup()
	if(!target)
		return
	var/mob/living/L = null
	if(isliving(AM))
		L = AM
		if(check_prefs && (!L.devourable || !L.allowmobvore))
			return
		if(check_keys && !L.ckey)
			return
		L.stop_pulling()
		L.status_at_least(STAT_WEAKENED, 3)
		L.reset_perspective() // Needed for food items that get gobbled with micros in them
		GLOB.prey_eaten_roundstat++
	if(target.reciever)		//We don't have to worry
		AM.unbuckle_all_mobs(TRUE)
		AM.forceMove(get_turf(target))
		extra(AM)
		return
	var/turf/place = locate(target.x, (target.y - 1), target.z)	//If the target is also a teleporter, let's pick a place to set them down next to the target.
																//Setting them ON the target will probably make an infinite loop, and that seems lame.
	AM.unbuckle_all_mobs(TRUE)
	AM.forceMove(place)
	extra(AM)

/obj/effect/dog_teleporter/proc/extra(atom/movable/AM as mob|obj)
	var/go = FALSE
	if(isobserver(AM))
		return
	playsound(src, teleport_sound, vol = 100, vary = 1, preference = /datum/preference/toggle/eating_noises, volume_channel = VOLUME_CHANNEL_VORE)
	playsound(target, teleport_sound, vol = 100, vary = 1, preference = /datum/preference/toggle/eating_noises, volume_channel = VOLUME_CHANNEL_VORE)
	if(isliving(AM))
		var/mob/living/L = AM
		if(teleport_message && L.client)
			to_chat(src, "[teleport_message]")
		go = TRUE
	if(isobj(AM))
		go = FALSE

	if(!go)
		return

	visible_message(span_danger("\The [AM] passes through \the [src]!"))
	if(throw_through)	//We will throw the target to the south!
		var/turf/throwtarg = locate(target.x, (target.y - 5), target.z)
		AM.throw_at(throwtarg, 10, 1)	//reverbfart.ogg

/obj/effect/dog_teleporter/food_gobbler
	teleport_sound = SFX_VORE_GULP
	teleport_message = span_notice("The thundering drum of the dog's heart beat throbs all around you, while the sweltering heat of its body soaks into you. It's soft and wet as a symphony of gurgles and glorps fills the steamy air!")

/obj/effect/dog_teleporter/food_gobbler/Crossed(atom/movable/AM)

	if(istype(AM, /obj/item/reagent_containers/food))
		gobble_food(AM)
	else return	..()

/obj/effect/dog_teleporter/food_gobbler/proc/gobble_food(obj/item/I)
	if(!isitem(I))
		return
	var/obj/effect/overmap/visitable/ship/simplemob/stardog/s = get_overmap_sector(z)
	if(s && istype(s,/obj/effect/overmap/visitable/ship/simplemob/stardog))
		if(!s.parent)
			return
		var/mob/living/simple_mob/vore/overmap/stardog/dog = s.parent
		dog.adjust_nutrition(I.reagents.total_volume)
		dog.adjust_affinity(25)
		playsound(src, teleport_sound, vol = 100, vary = 1, preference = /datum/preference/toggle/eating_noises, volume_channel = VOLUME_CHANNEL_VORE)
		visible_message(span_warning("The dog gobbles up \the [I]!"))
		if(dog.client)
			var/mob/thrower = I.throwing?.get_thrower()
			to_chat(dog, span_notice("[thrower ? "\The [thrower]" : "Someone"] feeds \the [I] to you!"))
		consumed(I, dog)
		GLOB.items_digested_roundstat++

/obj/effect/dog_teleporter/reciever
	name = "exit"
	desc = "It's too tight to go in there!"
	icon_state = "exita"
	pixel_y = -16
	reciever = TRUE

/obj/effect/dog_teleporter/reciever/invisible
	invisibility = INVISIBILITY_ABSTRACT
	reciever = TRUE
	id = "mouth_a"

/obj/effect/dog_teleporter/reciever/invisible/mouth_return
	invisibility = INVISIBILITY_ABSTRACT
	reciever = TRUE
	id = "mouth_b"

/obj/effect/dog_teleporter/exit
	name = "exit"
	desc = "You can see the light at the end of the tunnel!"
	icon_state = "exit_b"
	id = "exit"
	pixel_x = -16
	pixel_y = -16
	check_keys = TRUE
	check_prefs = FALSE	//We don't have to worry about it on the way out

/obj/effect/dog_teleporter/mouth_return
	name = "light"
	desc = "You can see the light shining in from above!"
	icon_state = "exit_b"
	id = "mouth_b"
	pixel_x = -16
	pixel_y = -16
	check_keys = TRUE
	check_prefs = FALSE	//We don't have to worry about it on the way out

/obj/effect/dog_teleporter/reciever/exit	//tee hee
	name = "exit"
	desc = "It's too tight to go in there!"
	icon_state = "exit"
	id = "exit"
	pixel_x = -16
	pixel_y = -16
	layer = ABOVE_TURF_LAYER
	plane = TURF_PLANE

/turf/simulated/floor/water/digestive_enzymes	//I'm sorry - Medical is going to be really angry. I hope people don't go ';HELP, HELP IN THE FLESH ABYSS!!!' but I know they will
	name = "digestive enzymes"
	desc = "A body of some kind of green fluid.  It seems shallow enough to walk through, if needed."
	icon = 'icons/turf/stomach_vr.dmi'
	icon_state = "composite"
	water_icon = 'icons/turf/stomach_vr.dmi'
	water_state = "enzyme_shallow"
	under_state = "flesh_floor"
	watercolor = "green"

	reagent_type = REAGENT_ID_SACID //why not
	outdoors = FALSE
	var/mob/living/simple_mob/vore/overmap/stardog/linked_mob
	var/mobstuff = TRUE		//if false, we don't care about dogs, and that's terrible

/// Something on it is still being digested. A field: it digests every 2 s while set.
/turf/simulated/floor/water/digestive_enzymes/var/we_process = FALSE
TRACKED(/turf/simulated/floor/water/digestive_enzymes, we_process)
CAPABILITIES(/turf/simulated/floor/water/digestive_enzymes)
	every(2 SECONDS, then(PROC_REF(digestive_enzymes_step)), when = nameof(we_process))

/turf/simulated/floor/water/digestive_enzymes/Entered(atom/movable/source)
	if(digest_stuff(source))
		set_we_process(TRUE)

/turf/simulated/floor/water/digestive_enzymes/hitby(atom/movable/source, datum/thrownthing/throwingdatum)
	if(digest_stuff(source))
		set_we_process(TRUE)

/turf/simulated/floor/water/digestive_enzymes/proc/digestive_enzymes_step(datum/act/timer/A)
	if(!digest_stuff())
		set_we_process(FALSE)

/turf/simulated/floor/water/digestive_enzymes/proc/can_digest(atom/movable/digest_target)
	. = FALSE
	if(digest_target.loc != src)
		return FALSE
	if(isitem(digest_target))
		var/obj/item/I = digest_target
		if(I.unacidable || I.throwing || I.is_incorporeal())
			return FALSE
		var/food = FALSE
		if(istype(I,/obj/item/reagent_containers/food))
			food = TRUE
		if(prob(95))	//Give people a chance to pick them up
			return TRUE
		I.visible_message(span_warning("\The [I] sizzles..."))
		var/yum = I.digest_act()	//Glorp
		if(istype(I , /obj/item/card))
			yum = 0		//No, IDs do not have infinite nutrition, thank you
		if(mobstuff && linked_mob && yum)
			if(food)
				yum += 50
			linked_mob.adjust_nutrition(yum)
		return TRUE
	if(isliving(digest_target))
		var/mob/living/L = digest_target
		if(L.unacidable || !L.digestable || L?.buckled_to() || dq_get_hovering(L) || L.throwing || L.is_incorporeal())
			return FALSE
		if(ishuman(L))
			var/mob/living/carbon/human/H = L
			if(!H.pl_suit_protected())
				return TRUE
			if(H.resting && !H.pl_head_protected())
				return TRUE
		else return TRUE

/turf/simulated/floor/water/digestive_enzymes/proc/digest_stuff(atom/movable/digest_target)	//I'm so sorry
	. = FALSE

	var/damage = 1
	if(mobstuff && !linked_mob)	//You might be wondering how we got here. It all started when I decided that I would make a vore level and make some of the turfs affect some mob somewhere in the world. So I used some convenient tools that people who are actually smart made, to make this horrible abomination.
		var/obj/effect/overmap/visitable/ship/simplemob/stardog/s = get_overmap_sector(z)
		if(s && istype(s,/obj/effect/overmap/visitable/ship/simplemob/stardog))
			rel_set(src, nameof(linked_mob), s.parent) //dogge

	if(linked_mob)	//Please for the love of all that is good, make all this mob shit its own proc, future me
		damage += clamp(((500 - linked_mob.nutrition) / 100), 1 , 5)
	var/list/stuff = list()
	for(var/thing in contents_of(src))
		if(can_digest(thing))
			stuff |= thing
	if(!stuff.len)
		return FALSE
	var/thing = pick(stuff)	//We only think about one thing at a time, otherwise things get wacky
	. = TRUE
	if(ishuman(thing))
		var/mob/living/carbon/human/H = thing
		if(!H)
			return
		balloon_alert_visible("*blub...*")
		if(H.stat == DEAD)
			H.unacidable = TRUE	//Don't touch this one again, we're gonna delete it in a second
			H.release_vore_contents()
			for(var/obj/item/W in contents_of(H))
				if(istype(W, /obj/item/organ/internal/mmi_holder/posibrain))
					var/obj/item/organ/internal/mmi_holder/MMI = W
					MMI.removed()
				if(istype(W, /obj/item/implant/backup) || istype(W, /obj/item/nif) || istype(W, /obj/item/organ))
					continue
				H.drop_from_inventory(W)
			if(linked_mob)
				var/how_much = H.mob_size + H.nutrition
				if(!H.ckey)
					how_much = how_much / 10	//Braindead mobs are worth less
				linked_mob.adjust_nutrition(how_much)
				H.mind?.vore_death = TRUE
				GLOB.prey_digested_roundstat++
			dissolved(H, src)	//glorp
			return
		H.burn_skin(damage)
		if(linked_mob)
			var/how_much = (damage * H.size_multiplier) * H.get_digestion_nutrition_modifier() * linked_mob.get_digestion_efficiency_modifier()
			if(!H.ckey)
				how_much = how_much / 10	//Braindead mobs are worth less
			linked_mob.adjust_nutrition(how_much)
	else if (isliving(thing))
		var/mob/living/L = thing
		if(!L)
			return
		balloon_alert_visible("*blub...*")
		if(L.stat == DEAD)
			L.unacidable = TRUE	//Don't touch this one again, we're gonna delete it in a second
			L.release_vore_contents()
			if(linked_mob)
				var/how_much = L.mob_size + L.nutrition
				if(!L.ckey)
					how_much = how_much / 10	//Braindead mobs are worth less
				linked_mob.adjust_nutrition(how_much)
			dissolved(L, src) //gloop
			return
		L.injure(INJURY_DIGESTION, damage, source = src)
		if(linked_mob)
			var/how_much = (damage * L.size_multiplier) * L.get_digestion_nutrition_modifier() * linked_mob.get_digestion_efficiency_modifier()
			if(!L.ckey)
				how_much = how_much / 10	//Braindead mobs are worth less
			linked_mob.adjust_nutrition(how_much)

/obj/structure/auto_flesh_door	//It's like a simple door, but it opens and closes automatically now and then!
	proximity_tracked = TRUE
	name = "flesh valve"
	density = TRUE
	opacity = TRUE
	anchored = TRUE
	can_atmos_pass = ATMOS_PASS_DENSITY

	icon = 'icons/turf/stomach_vr.dmi'
	icon_state = "fleshdoor"

	var/state = 0 //closed, 1 == open
	var/isSwitchingStates = 0
	var/countdown = 0
	var/knock_sound = SFX_EFFECTS_ATTACKBLOB
	var/static/list/open_sounds = list(
		'sound/vore/sunesound/prey/squish_01.ogg',
		'sound/vore/sunesound/prey/squish_02.ogg',
		'sound/vore/sunesound/prey/squish_03.ogg',
		'sound/vore/sunesound/prey/squish_04.ogg',
		'sound/vore/sunesound/prey/stomachmove.ogg'
		)
	var/faction = FACTION_MACROBACTERIA

CAPABILITIES(/obj/structure/auto_flesh_door)
	rolls(nameof(countdown), PROC_REF(roll_countdown))
	// the door only matters while someone can see it: ambient, so it runs while a client is near (STAT_RELEVANCE) and parks the rest of the time
	every(2 SECONDS, then(PROC_REF(auto_flesh_door_step)), when = STAT_RELEVANCE)
	op("flesh_door_hand_help", hand(), stance(I_HELP), label("Knock"), then(PROC_REF(interaction_hand_help)))
	op("flesh_door_hand_hurt", hand(), stance(I_HURT), label("Hammer on"), then(PROC_REF(interaction_hand_hurt)))
	op("flesh_door_hand_disarm", hand(), stance(I_DISARM), label("Hammer on"), then(PROC_REF(interaction_hand_disarm)))
	op("flesh_door_hand_grab", hand(), stance(I_GRAB), label("Hammer on"), then(PROC_REF(interaction_hand_grab)))

/// The help-stance input of interaction_hand: the shared handler with its stance.
/obj/structure/auto_flesh_door/proc/interaction_hand_help(datum/act/op/A)
	return interaction_hand(A, I_HELP)

/// The hurt-stance input of interaction_hand: the shared handler with its stance.
/obj/structure/auto_flesh_door/proc/interaction_hand_hurt(datum/act/op/A)
	return interaction_hand(A, I_HURT)

/// The disarm-stance input of interaction_hand: the shared handler with its stance.
/obj/structure/auto_flesh_door/proc/interaction_hand_disarm(datum/act/op/A)
	return interaction_hand(A, I_DISARM)

/// The grab-stance input of interaction_hand: the shared handler with its stance.
/obj/structure/auto_flesh_door/proc/interaction_hand_grab(datum/act/op/A)
	return interaction_hand(A, I_GRAB)

/// Rolled before init (rolls(), code/engine/lifeforms/rolls.dm): what the old Initialize() drew from the world RNG.
/obj/structure/auto_flesh_door/proc/roll_countdown(datum/roller/R)
	. = islist(countdown) ? list() + countdown : countdown
	. = R.number(50, 250)

/// Opens and closes (and squeezes whoever is inside) only while a mob is near; otherwise it waits.
/obj/structure/auto_flesh_door/proc/auto_flesh_door_step(datum/act/timer/A)
	if(!mob_near(world.view))
		return
	if(countdown <= 0)
		SwitchState()
	else
		countdown --
	if(!state)
		for(var/mob/living/L in contents_of(src.loc))
			if(isliving(L))
				L.status_at_least(STAT_WEAKENED, 3)
				if(prob(5))
					to_chat(L, span_warning("\The [src] throbs heavily around you..."))

/obj/structure/auto_flesh_door/attack_generic(mob/user, damage, attack_verb)
	. = ..()
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	if(!Adjacent(user))
		return
	else if(user.faction == faction)
		SwitchState()
	else if(!user.combat_mode)
		act_message(user, src, null, MSG_OTHERS(span_warningplain("%U% knocks on %T%.")), MSG_BLIND(span_warningplain("Someone knocks on %T%.")))
		playsound(src, knock_sound, 50, 0, 3)
		countdown -= 10
	else
		act_message(user, src, null, MSG_OTHERS(span_warning("%U% hammers on %T%!")), MSG_BLIND(span_warning("Someone hammers loudly on %T%!")))
		playsound(src, knock_sound, 50, 0, 3)
		countdown -= 25

/// Old attack_hand.
/obj/structure/auto_flesh_door/proc/interaction_hand(datum/act/op/A, stance)
	var/mob/user = A.actor
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	if(!Adjacent(user))
		return OP_OK
	else if(user.faction == faction)
		SwitchState()
	else if(stance == I_HELP)
		act_message(user, src, null, MSG_OTHERS(span_warningplain("%U% knocks on %T%.")), MSG_BLIND(span_warningplain("Someone knocks on %T%.")))
		playsound(src, knock_sound, 50, 0, 3)
		countdown -= 10
	else
		act_message(user, src, null, MSG_OTHERS(span_warning("%U% hammers on %T%!")), MSG_BLIND(span_warning("Someone hammers loudly on %T%!")))
		playsound(src, knock_sound, 50, 0, 3)
		countdown -= 25
	return OP_OK

/obj/structure/auto_flesh_door/CanPass(atom/movable/mover, turf/target)
	return !density

/obj/structure/auto_flesh_door/proc/SwitchState()
	if(state)
		Close()
	else
		Open()

/obj/structure/auto_flesh_door/proc/Open()
	isSwitchingStates = 1
	var/oursound = pick(open_sounds)
	playsound(src, oursound, 100, 1, preference = /datum/preference/toggle/digestion_noises , volume_channel = VOLUME_CHANNEL_VORE)
	flick("flesh-opening",src)
	after(src, 0.8 SECONDS, PROC_REF(open_finish))

/obj/structure/auto_flesh_door/proc/open_finish()
	set_density(FALSE)
	set_opacity(0)
	state = 1
	changed(src)
	isSwitchingStates = 0
	update_nearby_tiles()
	countdown = rand(10,20)
	layer = OBJ_LAYER
	plane = OBJ_PLANE

/obj/structure/auto_flesh_door/proc/Close()
	isSwitchingStates = 1
	var/oursound = pick(open_sounds)
	playsound(src, oursound, 100, 1, preference = /datum/preference/toggle/digestion_noises , volume_channel = VOLUME_CHANNEL_VORE)
	flick("flesh-closing",src)
	after(src, 0.8 SECONDS, PROC_REF(close_finish))

/obj/structure/auto_flesh_door/proc/close_finish()
	set_density(TRUE)
	set_opacity(1)
	state = 0
	changed(src)
	isSwitchingStates = 0
	update_nearby_tiles()
	countdown = rand(50,250)
	layer = ABOVE_MOB_LAYER
	plane = ABOVE_MOB_PLANE
	for(var/mob/living/L in contents_of(src.loc))
		if(isliving(L))
			L.status_at_least(STAT_WEAKENED, 3)
			act_message(L, src, MSG_SELF(span_danger("The weight of %T% closes in on you, squeezing you on all sides so tightly that you can hardly move! It throbs against you as the way is sealed, with you stuck in the middle!!!")), MSG_OTHERS(span_danger("%T% closes up on %U%!")))

/// The look (the draw sweep: from its template).
/obj/structure/auto_flesh_door/draw(datum/look/look)
	..()
	look.state("flesh-[state ? "open" : "closed"]")

/// Enzyme pools numb swimmers who opted out of digestion pain.
/turf/simulated/floor/water/digestive_enzymes/numbs_pain_of(mob/living/occupant)
	return !occupant.digest_pain

