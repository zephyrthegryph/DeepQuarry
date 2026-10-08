GLOBAL_LIST_INIT(cat_default_emotes, list(
	/datum/decl/emote/visible,
	/datum/decl/emote/visible/scratch,
	/datum/decl/emote/visible/drool,
	/datum/decl/emote/visible/nod,
	/datum/decl/emote/visible/sway,
	/datum/decl/emote/visible/sulk,
	/datum/decl/emote/visible/twitch,
	/datum/decl/emote/visible/twitch_v,
	/datum/decl/emote/visible/dance,
	/datum/decl/emote/visible/roll,
	/datum/decl/emote/visible/shake,
	/datum/decl/emote/visible/jump,
	/datum/decl/emote/visible/shiver,
	/datum/decl/emote/visible/collapse,
	/datum/decl/emote/visible/spin,
	/datum/decl/emote/visible/sidestep,
	/datum/decl/emote/audible,
	/datum/decl/emote/audible/hiss,
	/datum/decl/emote/audible/whimper,
	/datum/decl/emote/audible/gasp,
	/datum/decl/emote/audible/scretch,
	/datum/decl/emote/audible/choke,
	/datum/decl/emote/audible/moan,
	/datum/decl/emote/audible/gnarl,
	/datum/decl/emote/audible/purr,
	/datum/decl/emote/audible/purrlong
))

/mob/living/simple_mob/animal/passive/cat
	name = "cat"
	desc = "A domesticated, feline pet. Has a tendency to adopt crewmembers."
	tt_desc = "E Felis silvestris catus"
	icon = 'icons/mob/pets.dmi'
	icon_state = "cat2"
	item_state = "cat2"

	movement_cooldown = -1

	meat_amount = 1
	see_in_dark = 6 // Not sure if this actually works.
	response_help  = "pets"
	response_disarm = "gently pushes aside"
	response_harm   = "kicks"

	holder_type = /obj/item/holder/cat
	mob_size = MOB_SMALL

	has_langs = list(LANGUAGE_ANIMAL)

	var/mob/living/friend = null // Our best pal, who we'll follow. Meow.
	var/named = FALSE //have I been named yet?
	var/friend_name = null // Lock befriending to this character

/mob/living/simple_mob/animal/passive/cat/Initialize(mapload)
	set_icon_living("[initial(icon_state)]")
	set_icon_dead("[initial(icon_state)]_dead")
	set_icon_rest("[initial(icon_state)]_rest")
	return ..()

/mob/living/simple_mob/animal/passive/cat/get_available_emotes()
	return GLOB.cat_default_emotes.Copy()

/mob/living/simple_mob/animal/passive/cat/life_special_due()
	return TRUE

/mob/living/simple_mob/animal/passive/cat/life_special(datum/seq_frame/life/F)
	if(!src.stat && prob(2)) // spooky
		var/mob/observer/dead/spook = locate_in_list(range(src, 5), /mob/observer/dead)
		if(spook)
			var/turf/T = get_turf(spook)
			var/list/visible = list()
			for(var/obj/O in turf_contents_of_type(T, /obj))
				if(!O.invisibility && O.name)
					visible += O
			if(visible.len)
				var/atom/A = pick(visible)
				after(src, 0, TYPE_PROC_REF(/mob, visible_emote), with = list("suddenly stops and stares at something unseen[istype(A) ? " near [A]":""]."))

// Instakills mice.
/mob/living/simple_mob/animal/passive/cat/apply_melee_effects(atom/A)
	if(ismouse(A))
		var/mob/living/simple_mob/animal/passive/mouse/mouse = A
		if(mouse.get_endurance() < 20) // In case a badmin makes giant mice or something.
			mouse.splat()
			visible_emote(pick("bites \the [mouse]!", "toys with \the [mouse].", "chomps on \the [mouse]!"))
	else
		..()

/mob/living/simple_mob/animal/passive/cat/IIsAlly(mob/living/L)
	if(L == friend) // Always be pals with our special friend.
		return TRUE

	. = ..()

	if(.) // We're pals, but they might be a dirty mouse (or any other small fun to kill pest)...
		if(has_trait(L, TRAIT_AMBIENT_PEST_MOB))
			return FALSE // Cats and mice can never get along.

/mob/living/simple_mob/animal/passive/cat/verb/become_friends()
	set name = "Become Friends"
	set category = VERB_CAT_IC_GAME
	set src in view(1)

	var/mob/living/L = usr
	if(!istype(L))
		return // Fuck off ghosts.

	if(friend)
		if(friend == L)
			to_chat(L, span_notice("\The [src] is already your friend! Meow!"))
			return
		else
			to_chat(L, span_warning("\The [src] ignores you."))
			return

	// Adds friend_name var checks
	if(!friend_name || L.real_name == friend_name)
		rel_set(src, nameof(friend), L)
		face_atom(L)
		to_chat(L, span_notice("\The [src] is now your friend! Meow."))
		visible_emote(pick("nuzzles [friend].", "brushes against [friend].", "rubs against [friend].", "purrs."))

		if((ai_brain != null))
			var/datum/ai_brain/AI = ai_brain
			AI.set_follow(friend)
	else
		to_chat(L, span_notice("[src] ignores you."))


//RUNTIME IS ALIVE! SQUEEEEEEEE~
/mob/living/simple_mob/animal/passive/cat/runtime
	name = "Runtime"
	desc = "Her fur has the look and feel of velvet, and her tail quivers occasionally."
	tt_desc = "E Felis silvestris medicalis" // a hypoallergenic breed produced by NT for... medical purposes? Sure.
	gender = FEMALE
	icon_state = "cat"
	item_state = "cat"
	named = TRUE
	holder_type = /obj/item/holder/cat/runtime
	makes_dirt = 0

/mob/living/simple_mob/animal/passive/cat/kitten
	name = "kitten"
	desc = "D'aaawwww!"
	icon_state = "kitten"
	item_state = "kitten"
	gender = NEUTER
	holder_type = /obj/item/holder/cat/kitten

CAPABILITIES(/mob/living/simple_mob/animal/passive/cat/kitten)
	rolls(nameof(gender), pick_one(list(MALE, FEMALE)))

/mob/living/simple_mob/animal/passive/cat/black
	icon_state = "cat3"
	item_state = "cat3"

/mob/living/simple_mob/animal/passive/cat/black/beastmode
	movement_cooldown = 1

/mob/living/simple_mob/animal/passive/cat/bones
	name = "Bones"
	desc = "That's Bones the cat. He's a laid back, black cat. Meow."
	gender = MALE
	icon_state = "cat3"
	item_state = "cat3"
	named = TRUE
	holder_type = /obj/item/holder/cat/fluff/bones

// SPARKLY
/mob/living/simple_mob/animal/passive/cat/bluespace
	name = "bluespace cat"
	desc = "Shiny cat, shiny cat, it's not your fault."
	tt_desc = "E Felis silvestris argentum"
	icon_state = "bscat"
	icon_living = "bscat"
	icon_rest = null
	icon_dead = null
	makes_dirt = 0
	holder_type = /obj/item/holder/cat/bluespace

/// Vanishes instead of dying.
/mob/living/simple_mob/animal/passive/cat/bluespace/replace_death(gibbed)
	animate(src, alpha = 0, color = "#0000FF", time = 0.5 SECOND)
	expire(0.5 SECOND)
	return TRUE

/mob/living/simple_mob/animal/passive/cat/bread
	name = "bread cat"
	desc = "Brought lunch to work."
	tt_desc = "E Felis silvestris breadinum"
	icon_state = "breadcat"
	icon_living = "breadcat"
	icon_rest = "breadcat_rest"
	icon_dead = "breadcat_dead"
	makes_dirt = 0
	holder_type = /obj/item/holder/cat/breadcat

/mob/living/simple_mob/animal/passive/cat/original
	name = "original cat"
	desc = "Donut steal."
	tt_desc = "E Felis silvestris originalis"
	icon_state = "original"
	icon_living = "original"
	icon_rest = "original_rest"
	icon_dead = "original_dead"
	makes_dirt = 0
	holder_type = /obj/item/holder/cat/original

/mob/living/simple_mob/animal/passive/cat/cak
	name = "cak"
	desc = "Optimal combination of things?"
	tt_desc = "E Felis silvestris dessertus"
	icon_state = "cak"
	icon_living = "cak"
	icon_rest = "cak_rest"
	icon_dead = "cak_dead"
	makes_dirt = 0
	holder_type = /obj/item/holder/cat/cak

/mob/living/simple_mob/animal/passive/cat/space
	name = "space cat"
	desc = "Did someone write a song about this cat?"
	tt_desc = "E Felis silvestris stellaris"
	icon_state = "spacecat"
	icon_living = "spacecat"
	icon_rest = "spacecat_rest"
	icon_dead = "spacecat_dead"
	holder_type = /obj/item/holder/cat/spacecat
	makes_dirt = 0

	minbodytemp = 0				// Minimum "okay" temperature in kelvin
	maxbodytemp = 900			// Maximum of above
	heat_damage_per_tick = 3	// Amount of damage applied if animal's body temperature is higher than maxbodytemp
	cold_damage_per_tick = 2	// Same as heat_damage_per_tick, only if the bodytemperature it's lower than minbodytemp

	min_oxy = 0					// Oxygen in moles, minimum, 0 is 'no minimum'
	max_oxy = 0					// Oxygen in moles, maximum, 0 is 'no maximum'
	min_tox = 0					// Phoron min
	max_tox = 0					// Phoron max
	min_co2 = 0					// CO2 min
	max_co2 = 0					// CO2 max
	min_n2 = 0					// N2 min
	max_n2 = 0					// N2 max
	unsuitable_atoms_damage = 2	// This damage is taken when atmos doesn't fit all the requirements above

/datum/say_list/cat
	speak = list("Meow!","Esp!","Purr!","HSSSSS")
	emote_hear = list("meows","mews")
	emote_see = list("shakes their head", "shivers")
	say_maybe_target = list("Meow?","Mew?","Mao?")
	say_got_target = list("MEOW!","HSSSS!","REEER!")

MSG_DEF_SELF(cat/named, "%T% already has a name!")

/// Naming with a pen: asked, then written by cat_name_entered(). The one question is an asks() step of each op (a pen and a penlight).
CAPABILITIES(/mob/living/simple_mob/animal/passive/cat)
	op("name_with_pen", item(/obj/item/pen), label("Use"), needs(req_is(nameof(named), FALSE, because = MSG(cat/named))), asks(/datum/prompt/text, fields = list("title" = "Name", "question" = computed(PROC_REF(name_question)), "max_len" = MAX_NAME_LEN, "encode" = FALSE, "name_text" = TRUE, "timeout" = 0), step = "name"), then(PROC_REF(cat_name_entered)))
	op("name_with_penlight", item(/obj/item/flashlight/pen), label("Use"), needs(req_is(nameof(named), FALSE, because = MSG(cat/named))), asks(/datum/prompt/text, fields = list("title" = "Name", "question" = computed(PROC_REF(name_question)), "max_len" = MAX_NAME_LEN, "encode" = FALSE, "name_text" = TRUE, "timeout" = 0), step = "name"), then(PROC_REF(cat_name_entered)))

/mob/living/simple_mob/animal/passive/cat/proc/name_question(datum/act/A)
	return "Give 	he [name] a name"

/mob/living/simple_mob/animal/passive/cat/proc/cat_name_entered(datum/act/op/A)
	var/mob/user = A.actor
	var/tmp_name = sanitizeSafe(A.step_value("name"), MAX_NAME_LEN)
	if(named || !length(tmp_name))
		return OP_OK
	if(length(tmp_name) > 50)
		to_chat(user, span_notice("The name can be at most 50 characters long."))
	else
		to_chat(user, span_notice("You name 	he [name]. Meow!"))
		name = tmp_name
		named = TRUE
	return OP_OK

/obj/item/cat_box
	name = "faintly purring box"
	desc = "This box is purring faintly. You're pretty sure there's a cat inside it."
	icon = 'icons/obj/storage.dmi'
	icon_state = "box"
	var/cattype = /mob/living/simple_mob/animal/passive/cat

CAPABILITIES(/obj/item/cat_box)
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/cat_box/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(loc?.release_refusal(src, user))
		return TRUE
	var/turf/catturf = get_turf(src)
	to_chat(user, span_notice("You peek into \the [name]-- and a cat jumps out!"))
	new cattype(catturf)
	new /obj/item/stack/material/cardboard(catturf) //if i fits i sits
	consume(src, user)
	return TRUE

/obj/item/cat_box/black
	cattype = /mob/living/simple_mob/animal/passive/cat/black


// === merged from cat_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/mob/living/simple_mob/animal/passive/cat/runtime/load_default_bellies()
	. = ..()
	var/obj/belly/B = vore_selected
	B.name = "Stomach"
	B.desc = "The slimy wet insides of Runtime! Not quite as clean as the cat on the outside."

	B.own_emote_lists()
	B.emote_lists[DM_HOLD] = list(
		"Runtime's stomach kneads gently on you and you're fairly sure you can hear her start purring.",
		"Most of what you can hear are slick noises, Runtime breathing, and distant purring.",
		"Runtime seems perfectly happy to have you in there. She lays down for a moment to groom and squishes you against the walls.",
		"The CMO's pet seems to have found a patient of her own, and is treating them with warm, wet kneading walls.",
		"Runtime mostly just lazes about, and you're left to simmer in the hot, slick guts unharmed.",
		"Runtime's master might let you out of this fleshy prison, eventually. Maybe. Hopefully?")

	B.own_emote_lists()
	B.emote_lists[DM_DIGEST] = list(
		"Runtime's stomach is treating you rather like a mouse, kneading acids into you with vigor.",
		"A thick dollop of bellyslime drips from above while the CMO's pet's gut works on churning you up.",
		"Runtime seems to have decided you're food, based on the acrid air in her guts and the pooling fluids.",
		"Runtime's stomach tries to claim you, kneading and pressing inwards again and again against your form.",
		"Runtime flops onto their side for a minute, spilling acids over your form as you remain trapped in them.",
		"The CMO's pet doesn't seem to think you're any different from any other meal. At least, their stomach doesn't.")

	B.digest_messages_prey = list(
		"Runtime's stomach slowly melts your body away. Her stomach refuses to give up it's onslaught, continuing until you're nothing more than nutrients for her body to absorb.",
		"After an agonizing amount of time, Runtime's stomach finally manages to claim you, melting you down and adding you to her stomach.",
		"Runtime's stomach continues to slowly work away at your body before tightly squeezing around you once more, causing the remainder of your body to lose form and melt away into the digesting slop around you.",
		"Runtime's slimy gut continues to constantly squeeze and knead away at your body, the bulge you create inside of her stomach growing smaller as time progresses before soon dissapearing completely as you melt away.",
		"Runtime's belly lets off a soft groan as your body finally gives out, the cat's eyes growing heavy as it settles down to enjoy it's good meal.",
		"Runtime purrs happily as you slowly slip away inside of her gut, your body's nutrients are then used to put a layer of padding on the now pudgy cat.",
		"The acids inside of Runtime's stomach, aided by the constant motions of the smooth walls surrounding you finally manage to melt you away into nothing more mush. She curls up on the floor, slowly kneading the air as her stomach moves its contents — including you — deeper into her digestive system.",
		"Your form begins to slowly soften and break apart, rounding out Runtime's swollen belly. The carnivorous cat rumbles and purrs happily at the feeling of such a filling meal.")

// Ascian's Tactical Kitten
/mob/living/simple_mob/animal/passive/cat/tabiranth
	name = "Spirit"
	desc = "A small, inquisitive feline, who constantly seems to investigate his surroundings."
	icon = 'icons/mob/custom_items_mob.dmi'
	icon_state = "kitten"
	item_state = "kitten"
	gender = MALE
	holder_type = /obj/item/holder/cat/fluff/tabiranth
	friend_name = "Ascian"
	digestable = 0
	meat_amount = 0
	endurance = 50

/mob/living/simple_mob/animal/passive/cat/tabiranth/life_special_due()
	return TRUE

/mob/living/simple_mob/animal/passive/cat/tabiranth/life_special(datum/seq_frame/life/F)
	. = ..()
	if ((src.ai_brain != null) && src.friend)
		var/friend_dist = get_dist(src,src.friend)
		if (friend_dist <= 1)
			if (src.friend.stat >= DEAD || src.friend.is_critical())
				if (prob((src.friend.stat < DEAD)? 50 : 15))
					var/verb = pick("meows", "mews", "mrowls")
					after(src, 0, TYPE_PROC_REF(/mob, audible_emote), with = list(pick("[verb] in distress.", "[verb] anxiously.")))
			else
				if (prob(5))
					after(src, 0, TYPE_PROC_REF(/mob, visible_emote), with = list(pick("nuzzles [src.friend].",
									"brushes against [src.friend].",
									"rubs against [src.friend].",
									"purrs.")))
		else if (src.friend.vitality() <= 0.5)
			if (prob(10))
				var/verb = pick("meows", "mews", "mrowls")
				after(src, 0, TYPE_PROC_REF(/mob, audible_emote), with = list("[verb] anxiously."))

//Emergency teleport - Until a spriter makes something better
/mob/living/simple_mob/animal/passive/cat/tabiranth
	death_message = "teleports away!"

/mob/living/simple_mob/animal/passive/cat/tabiranth/on_death(gibbed)
	. = ..()
	cut_overlays()
	icon_state = ""
	flick("kphaseout",src)
	expire(1 SECOND) //Back from whence you came!

