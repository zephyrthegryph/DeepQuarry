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

	maxHealth = 5
	health = 5
	melee_damage_lower = 1
	melee_damage_upper = 3

	movement_cooldown = -1

	mob_size = MOB_MINISCULE
	pass_flags = PASSTABLE
//	can_pull_size = ITEMSIZE_TINY
//	can_pull_mobs = MOB_PULL_NONE
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

	var/body_color //brown, gray, white and black, leave blank for random

	var/list/datum/disease/rat_diseases

	can_be_drop_prey = TRUE
	can_be_drop_pred = FALSE
	species_sounds = "Mouse"

	pain_emote_1p = list("squeak", "squik")
	pain_emote_1p = list("squeaks", "squiks")

/mob/living/simple_mob/animal/passive/mouse/Destroy()
	GLOB.active_ghost_pods -= src
	return ..()

/mob/living/simple_mob/animal/passive/mouse/Initialize(mapload, keep_parent_data)
	. = ..()
	ghostjoin = TRUE
	ghostjoin_icon()
	GLOB.active_ghost_pods += src

	add_verb(src, /mob/living/proc/ventcrawl)
	add_verb(src, /mob/living/proc/hide)

	ADD_TRAIT(src, TRAIT_AMBIENT_PEST_MOB, ROUNDSTART_TRAIT)

	if(!keep_parent_data && name == initial(name))
		name = "[name] ([rand(1, 1000)])"
	real_name = name

	if(!body_color)
		body_color = pick( list("brown","gray","white","black") )
	icon_state = "mouse_[body_color]"
	item_state = "mouse_[body_color]"
	icon_living = "mouse_[body_color]"
	icon_dead = "mouse_[body_color]_dead"
	icon_rest = "mouse_[body_color]_sleep"
	if (!keep_parent_data && body_color != "rat")
		desc = "A small [body_color] rodent, often seen hiding in maintenance areas and making a nuisance of itself."
		holder_type = /obj/item/holder/mouse/rat
	if (body_color == "operative")
		holder_type = /obj/item/holder/mouse/operative
	if (body_color == "brown")
		holder_type = /obj/item/holder/mouse/brown
	if (body_color == "gray")
		holder_type = /obj/item/holder/mouse/gray
	if (body_color == "white")
		holder_type = /obj/item/holder/mouse/white
	if (body_color == "black")
		holder_type = /obj/item/holder/mouse/black

	if(prob(40))
		LAZYINITLIST(rat_diseases)
		rat_diseases += new /datum/disease/advance/random(rand(1, 5), 9, 1, infected = src)

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
			playsound(src, 'sound/effects/mouse_squeak.ogg', 35, 1)
	..()

/mob/living/simple_mob/animal/passive/mouse/death()
	layer = MOB_LAYER
	playsound(src, 'sound/effects/mouse_squeak_loud.ogg', 35, 1)
	if(client)
		client.time_died_as_mouse = world.time
	..()

/mob/living/simple_mob/animal/passive/mouse/cannot_use_vents()
	return

/mob/living/simple_mob/animal/passive/mouse/proc/splat()
	src.health = 0
	src.set_stat(DEAD)
	src.icon_dead = "mouse_[body_color]_splat"
	src.icon_state = "mouse_[body_color]_splat"
	layer = MOB_LAYER
	if(client)
		client.time_died_as_mouse = world.time

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

/mob/living/simple_mob/animal/passive/mouse/brown/Tom/Initialize(mapload)
	. = ..(mapload, TRUE)

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
	ai_holder_type = /datum/ai_holder/simple_mob/melee/evasive

/mob/living/simple_mob/animal/passive/mouse/rat/strong // In case you still want to be a jerk to your players for some reason.
	maxHealth = 20
	health = 20

/mob/living/simple_mob/animal/passive/mouse/operative
	name = "mouse operative"
	desc = "A cute mouse fitted with a custom blood red suit. Sneaky."
	body_color = "operative"
	icon_state = "mouse_operative"
	icon_rest = "mouse_operative_sleep"
	holder_type = /obj/item/holder/mouse/operative
	maxHealth = 35

	//It's wearing a void suit, it don't care about atmos
	health = 35
	min_oxy = 0
	max_oxy = 0
	min_tox = 0
	max_tox = 0
	min_co2 = 0
	max_co2 = 0
	min_n2 = 0
	max_n2 = 0
	maxbodytemp = 700

	ai_holder_type = /datum/ai_holder/simple_mob/melee/evasive

//The names Cheese... Agent Cheese
/mob/living/simple_mob/animal/passive/mouse/operative/agent_cheese
	name = "Agent Cheese"
	desc = "I like my cheese Swiss... not American."

/mob/living/simple_mob/animal/passive/mouse/operative/agent_cheese/Initialize(mapload)
	. = ..(mapload, TRUE)

// Mouse noises
/datum/say_list/mouse
	speak = list("Squeek!","SQUEEK!","Squeek?")
	emote_hear = list("squeeks","squeaks","squiks")
	emote_see = list("runs in a circle", "shakes", "scritches at something")

/mob/living/simple_mob/animal/passive/mouse/verb/set_mouse_colour()
	set name = "Set Mouse Colour"
	set category = "Abilities.Mouse"
	set desc = "Set the colour of your mouse."
	var/new_mouse_colour = tgui_input_list(usr, "Set Mouse Colour", "Pick a colour", list("brown","gray","white","black"))
	if(!new_mouse_colour) return
	icon_state = resting ? "mouse_[new_mouse_colour]_sleep" : "mouse_[new_mouse_colour]"
	item_state = "mouse_[new_mouse_colour]"
	icon_living = "mouse_[new_mouse_colour]"
	icon_dead = "mouse_[new_mouse_colour]_dead"
	icon_rest = "mouse_[new_mouse_colour]_sleep"
	desc = "A small [new_mouse_colour] rodent, often seen hiding in maintenance areas and making a nuisance of itself."
	holder_type = text2path("/obj/item/holder/mouse/[new_mouse_colour]")
	to_chat(src, span_notice("You are now a [new_mouse_colour] mouse!"))
	remove_verb(src,/mob/living/simple_mob/animal/passive/mouse/verb/set_mouse_colour)

/mob/living/simple_mob/animal/passive/mouse/white/virology
	name = "Fleming"
	desc = "A small white rodent, often found in Virology. This one isn't quite the nuisance!"

/mob/living/simple_mob/animal/passive/mouse/white/virology/Initialize(mapload)
	. = ..()
	name = initial(name)
	desc = initial(desc)
	rat_diseases += new /datum/disease/advance/random(2, 2, 1, infected = src)

/mob/living/simple_mob/animal/passive/mouse/white/virology/Crossed(atom/movable/AM)
	. = ..()

	if(isliving(AM) && !isnull(rat_diseases) && prob(20))
		var/mob/living/L = AM
		L.ContractDisease(pick(rat_diseases), BP_R_FOOT)


// === merged from mouse_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/mob/living/simple_mob/animal/passive/mouse
	nutrition = 20	//To prevent draining maint mice for infinite food. Low nutrition has no mechanical effect on simplemobs, so wont hurt mice themselves.
	vore_taste = "cheese"

	restrict_vore_ventcrawl = TRUE

	can_pull_size = ITEMSIZE_TINY // Rykka - Uncommented these. Not sure why they were commented out in the original Polaris files, maybe a mob rework mistake?
	can_pull_mobs = MOB_PULL_NONE // Rykka - Uncommented these. Not sure why they were commented out in the original Polaris files, maybe a mob rework mistake?

	desc = "A small rodent, often seen hiding in maintenance areas and making a nuisance of itself. And stealing cheese, or annoying the chef. SQUEAK! <3"

	movement_cooldown = 5
	universal_understand = 1

//Jank grabber that uses the 'attack_hand' insead of 'MouseDrop'
/mob/living/simple_mob/animal/passive/mouse/attack_hand(mob/user)
	var/mob/living/carbon/human/H = user
	if(holder_type && issmall(src) && istype(H) && !H.lying && Adjacent(H) && (a_intent == I_HELP && H.a_intent == I_HELP))
		if(!issmall(H) || !ishuman(src))
			get_scooped(H, (H == src))
		return
	return ..()

/mob/living/proc/mouse_scooped(mob/living/carbon/grabber, self_grab)

	if(!holder_type || buckled || pinned.len)
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
		grabber.equip_to_slot_if_possible(H, slot_back, 0, 1)
	else
		to_chat(grabber, span_notice("You scoop up \the [src]!"))
		to_chat(src, span_notice("\The [grabber] scoops you up!"))

	add_attack_logs(grabber, H.held_mob, "Scooped up", FALSE) // Not important enough to notify admins, but still helpful.
	return H

/mob/living/simple_mob/animal/passive/mouse/white/apple
	name = "Apple"
	desc = "Dainty, well groomed and cared for, her eyes glitter with untold knowledge..."
	gender = FEMALE

/mob/living/simple_mob/animal/passive/mouse/white/apple/Initialize(mapload, keep_parent_data)
	. = ..(mapload, TRUE)

/obj/item/holder/mouse/attack_self(mob/living/carbon/user)
	. = ..(user)
	if(.)
		return TRUE
	user.setClickCooldown(user.get_attack_speed())
	for(var/L in contents)
		if(isanimal(L))
			var/mob/living/simple_mob/S = L
			user.visible_message(span_notice("[user] [S.response_help] \the [S]."))

/mob/living/simple_mob/animal/passive/mouse/mining
	body_color = "brown"
	icon = 'icons/mob/animal.dmi'
	icon_state = "mouse_miner"
	item_state = "mouse_miner"
	icon_living = "mouse_miner"
	name = "Cooper"
	desc = "A lonely miner's best friend."

/mob/living/simple_mob/animal/passive/mouse/mining/Initialize(mapload)
	. = ..()

	add_verb(src,/mob/living/proc/ventcrawl)
	add_verb(src,/mob/living/proc/hide)
	icon_state = "mouse_miner"
	item_state = "mouse_miner"
	icon_living = "mouse_miner"
	icon_dead = "mouse_miner_dead"
	icon_rest = "mouse_miner_sleep"
	desc = "A lonely miner's best friend."


/mob/living/simple_mob/animal/passive/mouse/mining/splat()
	src.health = 0
	src.set_stat(DEAD)
	src.icon_dead = "mouse_miner_splat"
	src.icon_state = "mouse_miner_splat"
	layer = MOB_LAYER
	if(client)
		client.time_died_as_mouse = world.time

/mob/living/simple_mob/animal/passive/mouse/beastmode
	body_color = "white" // Always set white so it can be easily recoloured

/mob/living/simple_mob/animal/passive/mouse/beastmode/Initialize(mapload)
	. = ..()
	remove_verb(src,/mob/living/proc/ventcrawl) //No ventcrawl for hanner
