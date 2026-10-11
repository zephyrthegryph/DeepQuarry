/mob/living/simple_mob/animal/passive/mouse
	name = "mouse"
	real_name = "mouse"
	desc = "It's a small rodent."
	tt_desc = "E Mus musculus"
	icon_state = "mouse_gray"
	item_state = "mouse_gray"
	icon_living = "mouse_gray"
	icon_dead = "mouse_gray_dead"
	icon_rest = "mouse_gray_sleep"
	kitchen_tag = "rodent"

	endurance = 5
	melee_damage_lower = 1
	melee_damage_upper = 3

	movement_cooldown = -1

	mob_size = MOB_MINISCULE
	pass_flags = PASSTABLE
	layer = MOB_LAYER
	density = FALSE

	response_help  = "pets"
	response_disarm = "gently pushes aside"
	response_harm   = "stamps on"

	min_oxy = 16 //Require atleast 16kPA oxygen
	minbodytemp = 223		//Below -50 Degrees Celcius
	maxbodytemp = 323	//Above 50 Degrees Celcius

	has_langs = list(LANGUAGE_MOUSE)

	holder_type = /obj/item/holder/mouse
	meat_amount = 1
	butchery_loot = list()

	say_list_type = /datum/say_list/mouse

	hasthermals = FALSE
	ghostjoin = TRUE

	var/body_color //brown, gray, white and black, leave blank for random

	var/list/datum/affliction/contagion/rat_diseases

	can_be_drop_prey = TRUE
	can_be_drop_pred = FALSE
	species_sounds = "Mouse"

	pain_emote_1p = list("squeak", "squik")
	pain_emote_3p = list("squeaks", "squiks")

CAPABILITIES(/mob/living/simple_mob/animal/passive/mouse)
	configure(mob_movement(pull_size = ITEMSIZE_TINY, pull_mobs = MOB_PULL_NONE))
	verb_entry(/mob/living/proc/ventcrawl)
	verb_entry(/mob/living/proc/hide)
	param(nameof(keep_parent_data), pos = 1)
	op("mouse_hand_help", hand(), ungated(), stance(I_HELP), label("Scoop up"), then(PROC_REF(mouse_interaction_hand)))
	trait(TRAIT_AMBIENT_PEST_MOB)
	// numbered and coloured at random; a named mouse (keep_parent_data) keeps its name and description
	rolls(nameof(name), PROC_REF(roll_numbered_name), when = cond_not(nameof(keep_parent_data)))
	rolls(nameof(real_name), PROC_REF(roll_real_name), from = list(nameof(name)))
	rolls(nameof(body_color), pick_one(list("brown", "gray", "white", "black")), when = cond_not(nameof(body_color)))
	look_from(nameof(body_color), state = "mouse_*", item = "mouse_*", living = "mouse_*", dead = "mouse_*_dead", rest = "mouse_*_sleep")
	rolls(nameof(desc), PROC_REF(roll_desc), from = list(nameof(body_color)), when = cond_not(nameof(keep_parent_data)))
	rolls(nameof(holder_type), PROC_REF(roll_holder), from = list(nameof(body_color)))
	rolls(nameof(carries_disease), chance(40))
	owns_many(nameof(rat_diseases), /datum/affliction/contagion, starts = PROC_REF(start_diseases))

/// A mouse made from another keeps its name and look (its constructor param); a named mouse keeps its own.
/mob/living/simple_mob/animal/passive/mouse/var/keep_parent_data = FALSE
/// It was born carrying a disease (rolls()).
/mob/living/simple_mob/animal/passive/mouse/var/carries_disease = FALSE

/// Its description names its colour (rolls()); a rat keeps its own.
/mob/living/simple_mob/animal/passive/mouse/proc/roll_desc(datum/roller/R)
	if(body_color == "rat")
		return desc
	return "A small [body_color] rodent, often seen hiding in maintenance areas and making a nuisance of itself."

/// The holder it is scooped into matches its colour (rolls()); a colour with no holder of its own takes the rat's, unless the mouse keeps its own.
/mob/living/simple_mob/animal/passive/mouse/proc/roll_holder(datum/roller/R)
	var/path = text2path("/obj/item/holder/mouse/[body_color]")
	if(path)
		return path
	return keep_parent_data ? holder_type : /obj/item/holder/mouse/rat

/// The strains it starts with (owns_many(starts =)).
/mob/living/simple_mob/animal/passive/mouse/proc/start_diseases(current, mapload)
	. = list()
	if(carries_disease)
		. += new /datum/affliction/contagion/engineered/random(rand(1, 5), 9, 1, infected = src)

/mob/living/simple_mob/animal/passive/mouse/extrapolator_act(mob/living/user, obj/item/extrapolator/extrapolator, dry_run = FALSE)
	. = ..()
	EXTRAPOLATOR_ACT_ADD_DISEASES(., rat_diseases)

/mob/living/simple_mob/animal/passive/mouse/Crossed(atom/movable/AM as mob|obj)
	if(AM.is_incorporeal())
		return
	if( ishuman(AM) )
		if(!stat)
			var/mob/M = AM
			M.visible_message(span_blue("[icon2html(src,viewers(src))] Squeek!"))
			play_sfx(src, SFX_EFFECTS_MOUSE_SQUEAK)
	..()

/mob/living/simple_mob/animal/passive/mouse/on_death(gibbed)
	layer = MOB_LAYER
	play_sfx(src, SFX_EFFECTS_MOUSE_SQUEAK_LOUD)
	if(client)
		EXPIRY_STAMP(client, time_died_as_mouse, CLOCK_WORLD)
	..()

/mob/living/simple_mob/animal/passive/mouse/cannot_use_vents()
	return

/mob/living/simple_mob/animal/passive/mouse/proc/splat()
	src.set_stat(DEAD)
	src.set_icon_dead("mouse_[body_color]_splat")
	src.icon_state = "mouse_[body_color]_splat"
	layer = MOB_LAYER
	if(client)
		EXPIRY_STAMP(client, time_died_as_mouse, CLOCK_WORLD)

/*
 * Mouse types
 */

/mob/living/simple_mob/animal/passive/mouse/white
	body_color = "white"
	icon_state = "mouse_white"
	icon_rest = "mouse_white_sleep"
	holder_type = /obj/item/holder/mouse/white

/mob/living/simple_mob/animal/passive/mouse/gray
	body_color = "gray"
	icon_state = "mouse_gray"
	icon_rest = "mouse_gray_sleep"
	holder_type = /obj/item/holder/mouse/gray

/mob/living/simple_mob/animal/passive/mouse/brown
	body_color = "brown"
	icon_state = "mouse_brown"
	icon_rest = "mouse_brown_sleep"
	holder_type = /obj/item/holder/mouse/brown

//TOM IS ALIVE! SQUEEEEEEEE~K :)
/mob/living/simple_mob/animal/passive/mouse/brown/Tom
	name = "Tom"
	desc = "Jerry the cat is not amused."
	keep_parent_data = TRUE


/mob/living/simple_mob/animal/passive/mouse/black
	body_color = "black"
	icon_state = "mouse_black"
	icon_rest = "mouse_black_sleep"
	holder_type = /obj/item/holder/mouse/black

/mob/living/simple_mob/animal/passive/mouse/rat
	name = "rat"
	tt_desc = "E Rattus rattus"
	desc = "A large rodent, often seen hiding in maintenance areas and making a nuisance of itself."
	body_color = "rat"
	icon_state = "mouse_rat"
	icon_rest = "mouse_rat_sleep"
	holder_type = /obj/item/holder/mouse/rat

/mob/living/simple_mob/animal/passive/mouse/rat/strong // In case you still want to be a jerk to your players for some reason.
	endurance = 20

/mob/living/simple_mob/animal/passive/mouse/operative
	name = "mouse operative"
	desc = "A cute mouse fitted with a custom blood red suit. Sneaky."
	body_color = "operative"
	icon_state = "mouse_operative"
	icon_rest = "mouse_operative_sleep"
	holder_type = /obj/item/holder/mouse/operative
	endurance = 35

	//It's wearing a void suit, it don't care about atmos
	min_oxy = 0
	max_oxy = 0
	min_tox = 0
	max_tox = 0
	min_co2 = 0
	max_co2 = 0
	min_n2 = 0
	max_n2 = 0
	maxbodytemp = 700

//The names Cheese... Agent Cheese
/mob/living/simple_mob/animal/passive/mouse/operative/agent_cheese
	name = "Agent Cheese"
	desc = "I like my cheese Swiss... not American."
	keep_parent_data = TRUE


// Mouse noises
/datum/say_list/mouse
	speak = list("Squeek!","SQUEEK!","Squeek?")
	emote_hear = list("squeeks","squeaks","squiks")
	emote_see = list("runs in a circle", "shakes", "scritches at something")

/mob/living/simple_mob/animal/passive/mouse/verb/set_mouse_colour()
	set name = "Set Mouse Colour"
	set category = VERB_CAT_ABILITIES_MOUSE
	set desc = "Set the colour of your mouse."
	open_request(src, /datum/prompt/choice, PROC_REF(mouse_colour_chosen), answerer = src, title = "Pick a colour", question = "Set Mouse Colour", choices = list("brown","gray","white","black"), timeout = 0)

/mob/living/simple_mob/animal/passive/mouse/proc/mouse_colour_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/new_mouse_colour = A.answer.value
	icon_state = resting ? "mouse_[new_mouse_colour]_sleep" : "mouse_[new_mouse_colour]"
	item_state = "mouse_[new_mouse_colour]"
	set_icon_living("mouse_[new_mouse_colour]")
	set_icon_dead("mouse_[new_mouse_colour]_dead")
	set_icon_rest("mouse_[new_mouse_colour]_sleep")
	desc = "A small [new_mouse_colour] rodent, often seen hiding in maintenance areas and making a nuisance of itself."
	holder_type = text2path("/obj/item/holder/mouse/[new_mouse_colour]")
	to_chat(src, span_notice("You are now a [new_mouse_colour] mouse!"))
	grant(src, granted_verb(/mob/living/simple_mob/animal/passive/mouse/verb/set_mouse_colour, hidden = TRUE), src) // one colour change only

/mob/living/simple_mob/animal/passive/mouse/white/virology
	name = "Fleming"
	desc = "A small white rodent, often found in Virology. This one isn't quite the nuisance!"
	keep_parent_data = TRUE

/// Fleming always carries a strain of its own, besides what any mouse may.
/mob/living/simple_mob/animal/passive/mouse/white/virology/start_diseases(current, mapload)
	. = ..()
	. += new /datum/affliction/contagion/engineered/random(2, 2, 1, infected = src)

/mob/living/simple_mob/animal/passive/mouse/white/virology/Crossed(atom/movable/AM)
	. = ..()

	if(isliving(AM) && !isnull(rat_diseases) && prob(20))
		var/mob/living/L = AM
		L.expose_contagion(pick(rat_diseases), BP_R_FOOT)

// === merged from mouse_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/mob/living/simple_mob/animal/passive/mouse
	nutrition = 20	//To prevent draining maint mice for infinite food. Low nutrition has no mechanical effect on simplemobs, so wont hurt mice themselves.
	vore_taste = "cheese"

	restrict_vore_ventcrawl = TRUE


	desc = "A small rodent, often seen hiding in maintenance areas and making a nuisance of itself. And stealing cheese, or annoying the chef. SQUEAK! <3"

	movement_cooldown = 5
	universal_understand = 1

//Jank grabber that uses the 'attack_hand' insead of 'MouseDrop'

/// Old attack_hand: scooping.
/mob/living/simple_mob/animal/passive/mouse/proc/mouse_interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	. = OP_OK
	var/mob/living/carbon/human/H = user
	if(holder_type && issmall(src) && istype(H) && !H.lying && Adjacent(H) && !combat_mode)
		if(!issmall(H) || !ishuman(src))
			get_scooped(H, (H == src))
		return
	return OP_DECLINE

/mob/living/proc/mouse_scooped(mob/living/carbon/grabber, self_grab)

	if(!holder_type || src?.buckled_to() || LAZYLEN(pinned))
		return

	if(self_grab)
		if(incapacitated()) return
	else
		if(grabber.incapacitated()) return

	var/obj/item/holder/H = new holder_type(get_turf(src), src)
	grabber.put_in_hands(H)

	if(self_grab)
		to_chat(grabber, span_notice("\The [src] clambers onto you!"))
		to_chat(src, span_notice("You climb up onto \the [grabber]!"))
		grabber.equip_to_slot_if_possible(H, SLOT_ID_BACK, 0, 1)
	else
		to_chat(grabber, span_notice("You scoop up \the [src]!"))
		to_chat(src, span_notice("\The [grabber] scoops you up!"))

	add_attack_logs(grabber, H.held_mob, "Scooped up", FALSE) // Not important enough to notify admins, but still helpful.
	return H

/mob/living/simple_mob/animal/passive/mouse/white/apple
	name = "Apple"
	desc = "Dainty, well groomed and cared for, her eyes glitter with untold knowledge..."
	gender = FEMALE
	keep_parent_data = TRUE


CAPABILITIES(/obj/item/holder/mouse)
	configure(item_worn(slots = SLOT_EARS | SLOT_HEAD | SLOT_ID))
	op("self", in_hand(), label("Use"), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/holder/mouse/proc/interaction_self(datum/act/op/A)
	var/mob/living/carbon/user = A.actor
	user.setClickCooldown(user.get_attack_speed())
	for(var/L in contents)
		if(isanimal(L))
			var/mob/living/simple_mob/S = L
			act_message(user, S, null, MSG_OTHERS(span_notice("%U% [S.response_help] %T%.")))
	return TRUE

/mob/living/simple_mob/animal/passive/mouse/mining
	body_color = "miner"
	keep_parent_data = TRUE
	holder_type = /obj/item/holder/mouse/brown
	icon = 'icons/mob/animal.dmi'
	icon_state = "mouse_miner"
	item_state = "mouse_miner"
	icon_living = "mouse_miner"
	name = "Cooper"
	desc = "A lonely miner's best friend."

CAPABILITIES(/mob/living/simple_mob/animal/passive/mouse/mining)
	verb_entry(/mob/living/proc/ventcrawl)
	verb_entry(/mob/living/proc/hide)

/mob/living/simple_mob/animal/passive/mouse/mining/splat()
	src.set_stat(DEAD)
	src.set_icon_dead("mouse_miner_splat")
	src.icon_state = "mouse_miner_splat"
	layer = MOB_LAYER
	if(client)
		EXPIRY_STAMP(client, time_died_as_mouse, CLOCK_WORLD)

/mob/living/simple_mob/animal/passive/mouse/beastmode
	body_color = "white" // Always set white so it can be easily recoloured

CAPABILITIES(/mob/living/simple_mob/animal/passive/mouse/beastmode)
	verb_entry(/mob/living/proc/ventcrawl, hidden = TRUE) //No ventcrawl for hanner

// The rat's own disease strains; exposure passes on copies (expose_contagion()).

DECLARE_REGISTRY(/mob/living/simple_mob/animal/passive/mouse, REGISTRY_GHOST_PODS)
