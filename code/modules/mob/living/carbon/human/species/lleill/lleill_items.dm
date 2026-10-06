//Transparent Glamour (invisibility potion)

/obj/item/potion_material/glamour_transparent
	name = "transparent glamour"
	desc = "A shard of hardened white crystal that is clearly translucent."
	icon = 'icons/obj/glamour.dmi'
	icon_state = "transparent"
	base_reagent = /obj/item/potion_base/aqua_regia
	product_potion = /obj/item/reagent_containers/glass/bottle/potion/invisibility

/obj/item/reagent_containers/glass/bottle/potion/invisibility
	name = "transparent potion"
	desc = "A small white potion, the clear liquid inside can barely be seen at all."
	prefill = list(REAGENT_ID_GLAMOUR_INVIS = 1)

/datum/reagent/glamour_transparent
	name = REAGENT_GLAMOUR_INVIS
	id = REAGENT_ID_GLAMOUR_INVIS
	description = "This material is from somewhere else, it can barely be seen by the naked eye."
	taste_description = "nothingness"
	reagent_state = LIQUID
	color = "#ffffff"
	scannable = SCANNABLE_ADVANCED
	supply_conversion_value = REFINERYEXPORT_VALUE_RARE
	industrial_use = REFINERYEXPORT_REASON_MATSCI

/datum/reagent/glamour_transparent/affect_blood(mob/living/carbon/target, removed)
	if(!dq_get_cloaked(target))
		act_message(target, null, others = span_infoplain(span_bold("%U%") + " vanishes from sight."))
		target.cloak()
	target.bloodstr.clear_reagents() //instantly clears reagents afterwards
	target.ingested.clear_reagents()
	target.touching.clear_reagents()
	after(target, 1 MINUTE, TYPE_PROC_REF(/mob/living, glamour_cloak_expires))

//Shrinking Glamour (scaling potion)

/obj/item/potion_material/glamour_shrinking
	name = "shrinking glamour"
	desc = "A soft clump of white material that seems to shrink at your touch."
	icon = 'icons/obj/glamour.dmi'
	icon_state = "shrinking"
	base_reagent = /obj/item/potion_base/aqua_regia
	product_potion = /obj/item/reagent_containers/glass/bottle/potion/scaling

/obj/item/reagent_containers/glass/bottle/potion/scaling
	name = "scaling potion"
	desc = "A small white potion, the clear liquid inside can barely be seen at all."
	prefill = list(REAGENT_ID_GLAMOUR_SCALE = 1)

/datum/reagent/glamour_scaling
	name = REAGENT_GLAMOUR_SCALE
	id = REAGENT_ID_GLAMOUR_SCALE
	description = "This material is from somewhere else, it appears to change volumes readily at a glance."
	taste_description = "difficult to discern"
	reagent_state = LIQUID
	color = "#ffffff"
	scannable = SCANNABLE_ADVANCED
	wiki_flag = WIKI_SPOILER
	supply_conversion_value = REFINERYEXPORT_VALUE_RARE
	industrial_use = REFINERYEXPORT_REASON_MATSCI

/datum/reagent/glamour_scaling/affect_blood(mob/living/carbon/target, removed)
	if(!(/mob/living/proc/set_size in target.verbs))
		to_chat(target, span_warning("You feel as though you could change size at any moment."))
		grant(target, granted_verb(/mob/living/proc/set_size), target)
	target.bloodstr.clear_reagents() //instantly clears reagents afterwards
	target.ingested.clear_reagents()
	target.touching.clear_reagents()

//Twinkling Glamour (Sparkling potion - Gives darksight)

/obj/item/potion_material/glamour_twinkling
	name = "twinkling glamour"
	desc = "A sheet of white material that twinkles on its own accord."
	icon = 'icons/obj/glamour.dmi'
	icon_state = "twinkling"
	base_reagent = /obj/item/potion_base/aqua_regia
	product_potion = /obj/item/reagent_containers/glass/bottle/potion/darksight

/obj/item/reagent_containers/glass/bottle/potion/darksight
	name = "twinling potion"
	desc = "A small white potion, the thin white liquid inside twinkles brightly."
	prefill = list(REAGENT_ID_GLAMOUR_TWINKLING = 1)

/datum/reagent/glamour_twinkling
	name = REAGENT_GLAMOUR_TWINKLING
	id = REAGENT_ID_GLAMOUR_TWINKLING
	description = "This material is from somewhere else, it appears to be twinkling."
	taste_description = "bright"
	reagent_state = LIQUID
	color = "#ffffff"
	scannable = SCANNABLE_ADVANCED
	supply_conversion_value = REFINERYEXPORT_VALUE_RARE
	industrial_use = REFINERYEXPORT_REASON_MATSCI

/datum/reagent/glamour_twinkling/affect_blood(mob/living/carbon/human/target, removed)
	if(target.species.darksight < 10)
		to_chat(target, span_warning("You can suddenly see much better than before."))
		proto_private(target, nameof(target.species)) // per-mob change: never mutate the shared species
		target.species.darksight = 10
	if(target.disabilities & NEARSIGHTED)
		target.disabilities &= ~NEARSIGHTED
		to_chat(target, span_warning("Everything is much less blurry."))
	target.bloodstr.clear_reagents() //instantly clears reagents afterwards
	target.ingested.clear_reagents()
	target.touching.clear_reagents()

//Glamour Cell (variant of capture crystal)

/obj/item/capture_crystal/glamour
	name = "glamour cell"
	desc = "A large but light round ball of glamour that glows from somewhere within."
	icon = 'icons/obj/glamour.dmi'

/obj/item/capture_crystal/glamour/animate_action(atom/thing)
	var/image/coolanimation = image('icons/obj/glamour.dmi', null, "animation")
	coolanimation.plane = PLANE_LIGHTING_ABOVE
	thing.overlays += coolanimation
	after(src, 1.4 SECOND, PROC_REF(animate_action_finished), with = list(thing, coolanimation))

//Face of Glamour (creates a clone of a target)

/obj/item/glamour_face
	name = "face of glamour"
	desc = "A piece of glamour that is formed vaguely into the shape of a face."
	icon = 'icons/obj/glamour.dmi'
	icon_state = "face"
	var/mob/living/homunculus // relation: the homunculus we summoned

CAPABILITIES(/obj/item/glamour_face)
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/glamour_face/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(!homunculus)
		var/list/targets = list()
		for(var/mob/living/carbon/human/M in REGISTRY_MEMBERS(REGISTRY_MOBS))
			if(M.z != user.z || get_dist(user,M) > 10)
				continue
			if(!M.allow_mimicry)
				continue
			targets |= M

		if(!targets.len)
			to_chat(user, span_warning("There are no appropriate targets in range."))
			return TRUE

		open_request(src, /datum/prompt/choice, PROC_REF(homunculus_target_chosen), answerer = user, title = "homunculus", question = "Which target do you wish to create a homunculus of?", choices = targets, ask_flags = ASK_HELD | ASK_CAPABLE, timeout = 0)
		return TRUE
	if(homunculus)
		open_request(src, /datum/prompt/choice, PROC_REF(homunculus_action_chosen), answerer = user, title = "Actions", question = "What would you like to do with your homunculus?", choices = list("Recall", "Speak Through", "Cancel"), buttons = TRUE, ask_flags = ASK_HELD | ASK_CAPABLE, timeout = 0)
	return TRUE

/obj/item/glamour_face/proc/homunculus_target_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/mob/living/carbon/human/chosen_target = A.answer.value
	if(homunculus)
		return
	if(chosen_target)
		var/spawnloc = get_turf(user)
		var/mob/living/simple_mob/homunculus/H = new(spawnloc)
		H.name = chosen_target.name
		H.desc = chosen_target.desc
		H.icon = chosen_target.icon
		H.icon_state = chosen_target.icon_state
		H.copy_overlays(chosen_target, TRUE)
		H.resize(chosen_target.size_multiplier, ignore_prefs = TRUE)
		rel_set(src, nameof(homunculus), H)
		rel_set(H, nameof(H.owner), src)

/obj/item/glamour_face/proc/homunculus_action_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/h_action = A.answer.value
	var/mob/living/simple_mob/homunculus/H = homunculus
	if(!H)
		return
	if(h_action == "Recall")
		act_message(H, null, others = span_infoplain(span_bold("%U%") + " returns to the face."))
		spent(H) // the framework clears our homunculus view
		return
	if(h_action == "Speak Through")
		open_request(src, /datum/prompt/text, PROC_REF(homunculus_words_entered), answerer = user, title = "Speak Through", question = "What should the homunculus say:", ask_flags = ASK_HELD | ASK_CAPABLE, timeout = 0)

/obj/item/glamour_face/proc/homunculus_words_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/living/simple_mob/homunculus/H = homunculus
	H?.say(A.answer.value)


//Speaking Glamour (universal translator)

/obj/item/universal_translator/glamour
	name = "speaking glamour"
	desc = "A shard of glamour that translates all known language for the user."
	icon = 'icons/obj/glamour.dmi'
	icon_state = "translator"

/obj/item/universal_translator/glamour/hear_talk(mob/M, list/message_pieces, verb)
	if(!translation_enabled || !istype(M))
		return

	//Show the "I heard something" animation.
	if(mult_icons)
		flick("[initial(icon_state)]2",src)

	//Handheld or pocket only.
	if(!isliving(loc))
		return

	var/mob/living/L = loc
	if(visual && ((L.sdisabilities & BLIND) || L.has_status(STAT_BLINDED)))
		return
	if(audio && ((L.sdisabilities & DEAF) || L.has_status(STAT_DEAFENED)))
		return

	// Using two for loops kinda sucks, but I think it's more efficient
	// to shortcut past string building if we're just going to discard the string
	// anyways.
	if(user_understands(M, L, message_pieces))
		return

	var/new_message = ""

	for(var/datum/multilingual_say_piece/S in message_pieces)
		if(S.speaking.flags & NONVERBAL)
			continue

		new_message += (S.message + " ")

	if(!L.say_understands(null, langset()))
		new_message = langset().scramble(new_message)

	to_chat(L, span_filter_say("<i><b>[src]</b> translates, </i>\"<span class='[langset().colour]'>[new_message]</span>\""))

//Teleporter ring

/obj/structure/glamour_ring
	name = "glamour ring"
	desc = "A ring of glowing white, oddly reflective material."
	icon = 'icons/obj/glamour.dmi'
	icon_state = "ring"
	density = 0
	anchored = 1

	var/connected_mob
	var/area_name

// ALLOW(init/INSTANCE_STATE): names itself after the area it is placed in
/obj/structure/glamour_ring/Initialize(mapload)
	. = ..()
	var/area/A = get_area(src)
	area_name = A.name
	name = "[area_name] glamour ring"

/obj/structure/glamour_ring/proc/ring_left_alone(mob/living/M)
	to_chat(M, span_warning("You leave the glamour ring alone."))

/obj/structure/glamour_ring/proc/ring_broken(mob/living/M)
	if(loc?.release_refusal(src, M))
		return
	var/mob/living/carbon/human/L = connected_mob
	to_chat(M, span_warning("You have destroyed \the [src]."))
	src.visible_message(span_infoplain(span_bold("\The [M]") + " has broken apart \the [src]."))
	if(M != connected_mob && connected_mob)
		to_chat(connected_mob, span_warning("\The [src] has been destroyed by \the [M]."))
	if(istype(L) && istype(L.species, /datum/species/lleill))
		own_take_member(L, nameof(L.teleporters), src)
	consume(src, M)

DECLARE_INTERACTIONS(/obj/structure/glamour_ring, INTERACT_HAND_UNGATED(null, PROC_REF(interaction_hand)))

/// Old attack_hand.
/obj/structure/glamour_ring/proc/interaction_hand(mob/living/M, obj/item/held, datum/interaction/interaction)

	var/mob/living/carbon/human/L = connected_mob
	if(!istype(L))
		return TRUE

	if(M == L)
		open_request(src, /datum/prompt/choice, PROC_REF(ring_action_chosen), answerer = M, title = "Destroy ring", question = "Do you want to destroy the ring, or restore energy?", choices = list("Yes", "No", "Restore Energy"), buttons = TRUE, ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE, timeout = 0)
	else
		open_request(src, /datum/prompt/choice, PROC_REF(ring_action_chosen), answerer = M, title = "Destroy ring", question = "Do you want to destroy the ring, the owner of it may be aware that you have done this?", choices = list("Yes", "No"), buttons = TRUE, ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE, timeout = 0)
	return TRUE

/obj/structure/glamour_ring/proc/ring_action_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/living/M = A.request.answerer
	var/m_action = A.answer.value
	var/mob/living/carbon/human/L = connected_mob
	if(!istype(L) || m_action == "No")
		return
	var/datum/species/lleill/LL = L.species

	if(m_action == "Yes")
		to_chat(M, span_warning("You begin to break the lines of the glamour ring."))
		om_task_timed(M, 10 SECONDS, target = src, receiver = src, on_done = PROC_REF(ring_broken), done_args = list(M), on_fail = PROC_REF(ring_left_alone), fail_args = list(M))
		return

	if(m_action == "Restore Energy")
		if(!COOLDOWN_FINISHED(LL, ring_cooldown))
			to_chat(M, span_warning("You must wait a while before drawing energy from the glamour again."))
			return
		om_task_start(/datum/om/task/timed/glamour_ring_attack_hand_glamour_ring, M, src, receiver = src, lleill_mob = L)
		return

/datum/om/task/timed/glamour_ring_attack_hand_glamour_ring
	duration = 10 SECONDS
	complete_proc = /obj/structure/glamour_ring/proc/attack_hand_glamour_ring_done
	cancel_proc = /obj/structure/glamour_ring/proc/attack_hand_glamour_ring_failed
	/// The lleill drawing energy (their species is made private before it is changed).
	var/mob/living/carbon/human/lleill_mob

/obj/structure/glamour_ring/proc/attack_hand_glamour_ring_done(datum/om/task/timed/glamour_ring_attack_hand_glamour_ring/task)
	if(!task.lleill_mob)
		return
	var/datum/species/lleill/LL = proto_private(task.lleill_mob, nameof(/datum/dna::species)) // per-mob change: never mutate the shared species
	if(!istype(LL))
		return
	COOLDOWN_START(LL, ring_cooldown, 10 MINUTES)
	LL.lleill_energy = min((LL.lleill_energy + 75),LL.lleill_energy_max)

/obj/structure/glamour_ring/proc/attack_hand_glamour_ring_failed(datum/om/task/timed/glamour_ring_attack_hand_glamour_ring/task)
	var/mob/living/M = task.actor
	to_chat(M, span_warning("You stop drawing energy."))
	return

//Glamour Helm

/obj/item/clothing/mask/gas/glamour
	desc = "A bubble-like helmet of glamour that can protect your face from the atmosphere, or lack thereof, outside."
	name = "glamour bubble"
	icon = 'icons/obj/glamour.dmi'
	icon_state = "bubble"
	item_flags = BLOCK_GAS_SMOKE_EFFECT | AIRTIGHT | ALLOW_SURVIVALFOOD | INFINITE_AIR

//Glamour Pockets

/obj/item/clothing/under/permit/glamour
	name = "pocket of glamour"
	desc = "A small crystal of glamour that is capable of storing small items inside of it."
	icon = 'icons/obj/glamour.dmi'
	icon_state = "pocket"

//Unstable Glamour

/obj/item/glamour_unstable
	name = "unstable glamour"
	desc = "A bright white glowing object that appears to move about on its own."
	icon = 'icons/obj/glamour.dmi'
	icon_state = "unstable"
	w_class = ITEMSIZE_SMALL
	var/tele_range = 4
	var/tf_type = /mob/living/simple_mob/animal/passive/mouse
	var/tf_possible_types = list(
		"mouse" = /mob/living/simple_mob/animal/passive/mouse,
		"rat" = /mob/living/simple_mob/animal/passive/mouse/rat,
		"mothroach" = /mob/living/simple_mob/animal/passive/mothroach,
		"giant rat" = /mob/living/simple_mob/vore/aggressive/rat,
		"dust jumper" = /mob/living/simple_mob/vore/alienanimals/dustjumper,
		"woof" = /mob/living/simple_mob/vore/woof,
		"corgi" = /mob/living/simple_mob/animal/passive/dog/corgi,
		"cat" = /mob/living/simple_mob/animal/passive/cat,
		"chicken" = /mob/living/simple_mob/animal/passive/chicken,
		"cow" = /mob/living/simple_mob/animal/passive/cow,
		"lizard" = /mob/living/simple_mob/animal/passive/lizard,
		"rabbit" = /mob/living/simple_mob/vore/rabbit,
		"fox" = /mob/living/simple_mob/animal/passive/fox,
		"fennec" = /mob/living/simple_mob/vore/fennec,
		"cute fennec" = /mob/living/simple_mob/animal/passive/fennec,
		"fennix" = /mob/living/simple_mob/vore/fennix,
		"red panda" = /mob/living/simple_mob/vore/redpanda,
		"opossum" = /mob/living/simple_mob/animal/passive/opossum,
		"horse" = /mob/living/simple_mob/vore/horse,
		"goose" = /mob/living/simple_mob/animal/space/goose,
		"sheep" = /mob/living/simple_mob/vore/sheep,
		"space bumblebee" = /mob/living/simple_mob/vore/bee,
		"space bear" = /mob/living/simple_mob/animal/space/bear,
		"voracious lizard" = /mob/living/simple_mob/vore/aggressive/dino,
		"giant frog" = /mob/living/simple_mob/vore/aggressive/frog,
		"jelly blob" = /mob/living/simple_mob/vore/jelly,
		"wolf" = /mob/living/simple_mob/vore/wolf,
		"direwolf" = /mob/living/simple_mob/vore/wolf/direwolf,
		"great wolf" = /mob/living/simple_mob/vore/greatwolf,
		"sect queen" = /mob/living/simple_mob/vore/sect_queen,
		"sect drone" = /mob/living/simple_mob/vore/sect_drone,
		"panther" = /mob/living/simple_mob/vore/aggressive/panther,
		"giant snake" = /mob/living/simple_mob/vore/aggressive/giant_snake,
		"deathclaw" = /mob/living/simple_mob/vore/aggressive/deathclaw,
		"otie" = /mob/living/simple_mob/vore/otie,
		"mutated otie" =/mob/living/simple_mob/vore/otie/feral,
		"red otie" = /mob/living/simple_mob/vore/otie/red,
		"defanged xenomorph" = /mob/living/simple_mob/vore/xeno_defanged,
		"catslug" = /mob/living/simple_mob/vore/alienanimals/catslug,
		"monkey" = /mob/living/carbon/human/monkey,
		"wolpin" = /mob/living/carbon/human/wolpin,
		"sparra" = /mob/living/carbon/human/sparram,
		"saru" = /mob/living/carbon/human/sergallingm,
		"sobaka" = /mob/living/carbon/human/sharkm,
		"farwa" = /mob/living/carbon/human/farwa,
		"neaera" = /mob/living/carbon/human/neaera,
		"stok" = /mob/living/carbon/human/stok,
		"weretiger" = /mob/living/simple_mob/vore/weretiger,
		"dragon" = /mob/living/simple_mob/vore/bigdragon/friendly,
		"leopardmander" = /mob/living/simple_mob/vore/leopardmander
		)

DECLARE_INTERACTIONS(/obj/item/glamour_unstable, \
	INTERACT_USE(null, PROC_REF(interaction_self)), \
	INTERACT_HAND_DEFAULT("Pick up", PROC_REF(glamour_pick_up)), \
)

/// Old attack_self.
/obj/item/glamour_unstable/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	var/mob/living/M = user
	if(!istype(M))
		return TRUE
	act_message(user, src, MSG_SELF(span_danger("You trigger %T%!")), MSG_OTHERS(span_warning("%U% triggers %T%!")))
	fx_sparks(get_turf(src), 5)
	var/effect_choice = rand(1,4)
	switch(effect_choice)
		if(1) //teleport
			blink_mob(M)
		if(2) //mob_tf, uses polymorph potion code
			if(!M.allow_spontaneous_tf)
				M.status_adjust(STAT_WEAKENED, 50)
			else
				mob_tf(M)
		if(3)
			size_change(M)
		if(4)
			M.apply_effect(200, IRRADIATE)
	return TRUE

/obj/item/glamour_unstable/proc/blink_mob(mob/living/L)
	var/starting_loc = (get_turf(src))
	var/list/target_loc = list()
	for(var/turf/simulated/floor/T in range(tele_range, starting_loc)) //Only appear on floors
		if(!istype(T))
			continue
		if(T == starting_loc)
			continue
		target_loc |= T

	if(target_loc.len)
		var/final_loc = pick(target_loc)
		do_teleport(L, final_loc, asoundin = 'sound/effects/phasein.ogg')

/obj/item/glamour_unstable/proc/mob_tf(mob/living/target)
	var/mob/living/M = target
	if(!istype(M))
		return
	if(M.tf_mob_holder)
		M.revert_mob_tf()
		return
	else
		if(M.stat == DEAD)	//We can let it undo the TF, because the person will be dead, but otherwise things get weird.
			return
		var/mob/living/new_mob = spawn_mob(M)

		M.tf_into(new_mob)


/obj/item/glamour_unstable/proc/spawn_mob(mob/living/target)
	var/choice = pick(tf_possible_types)
	tf_type = tf_possible_types[choice]
	if(!ispath(tf_type))
		return
	var/new_mob = new tf_type(get_turf(target))
	return new_mob

/obj/item/glamour_unstable/proc/size_change(mob/living/L)
	var/new_size = (rand(25,200))/100
	L.resize(new_size, ignore_prefs = FALSE)

/// Picking the unstable glamour up bare-handed may set it off.
/obj/item/glamour_unstable/proc/glamour_pick_up(mob/user, obj/item/held, datum/interaction/interaction)
	. = TRUE
	interaction_pick_up(user, held, interaction)

	var/mob/living/M = user
	if(!istype(M))
		return

	if(ishuman(M))
		var/mob/living/carbon/human/H = user
		var/obj/item/clothing/gloves/G = H.get_equipped_item(SLOT_ID_GLOVES)
		if(istype(G) && ((G.flags & THICKMATERIAL && prob(70)) || istype(G, /obj/item/clothing/gloves/gauntlets)))
			return

		if((H.species.name == SPECIES_HANNER) || (H.species.name == SPECIES_LLEILL))
			return

		attack_self(H)

/// The transparent glamour wears off.
/mob/living/proc/glamour_cloak_expires()
	if(dq_get_cloaked(src))
		uncloak()
		act_message(src, null, others = span_infoplain(span_bold("%U%") + " appears as if from thin air."))
