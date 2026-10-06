//Code for chaplains pet.
/mob/living/simple_mob/clockwork
	name = "Clockwork Marauder"
	desc = "The stalwart apparition of a clockwork flame guardian. It's eternal flame glows a firey-red."
	tt_desc = "Aeterna flamma armis"
	biology = BIOLOGY_SYNTHETIC // Animated brass armour.
	icon = 'icons/mob/clockwork_mobs.dmi'
	icon_state = "clockwork_marauder_r"
	item_state = "clockwork_marauder_r"
	icon_living = "clockwork_marauder_r"
	icon_dead = "fallen_armor"
	icon_rest = "clockwork_marauder_r"

	movement_cooldown = 0.5 SECONDS

	see_in_dark = 6 // Not sure if this actually works.


	response_help  = "pats"
	response_disarm = "gently pushes aside"
	response_harm   = "kicks"

	min_oxy = 16 //Require atleast 16kPA oxygen
	minbodytemp = 223		//Below -50 Degrees Celcius
	maxbodytemp = 323	//Above 50 Degrees Celcius

	has_langs = list("Occursus")
/*	speak_chance = 1
	speak = list("Heretics!","Burn them!","Protect believers!","Hail Helios")
	speak_emote = list("crackles", "burns")
	emote_hear = list("crackles","burns")
	emote_see = list("twists their sword", "adjusts their shield")
	say_maybe_target = list("Who?","Strange.")
	say_got_target = list("Purge!","Cleanse!","Burn!") */

	meat_amount = 0
	meat_type = /obj/item/reagent_containers/food/snacks/meat

	var/turns_since_scan = 0
	var/mob/flee_target

	can_be_drop_prey = FALSE

/mob/living/simple_mob/clockwork/life_special_due()
	return TRUE

/mob/living/simple_mob/clockwork/life_special(datum/seq_frame/life/F)
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



//Basic friend AI
/*/mob/living/simple_animal/clockwork/fluff
	var/mob/living/carbon/human/friend
	var/befriend_job = null

/mob/living/simple_animal/cat/fluff/verb/become_friends()
	set name = "Become Friends"
	set category = VERB_CAT_ABILITIES_GENERAL
	set src in view(1)

	if(!friend)
		var/mob/living/carbon/human/H = usr
		if(istype(H) && (!befriend_job || H.job == befriend_job))
			friend = usr
			. = 1
	else if(usr == friend)
		. = 1 //already friends, but show success anyways

	if(.)
		set_dir(get_dir(src, friend))
		visible_emote(pick("nuzzles [friend].",
							"brushes against [friend].",
							"rubs against [friend].",
							"purrs."))
	else
		usr << span_notice("[src] ignores you.")
	return */

/mob/living/simple_mob/clockwork/fluff/Ignis
	name = "Ignis"
	desc = "The stalwart apparition of a clockwork flame guardian. This one appears to be  to be have been somehow modified to be 'docile', it's living fire turned blue."
//	tt_desc = "Aeterna flamma armis" //Chaplains new pet!
	icon = 'icons/mob/clockwork_mobs.dmi'
	icon_state = "ignis"
	item_state = "ignis"

