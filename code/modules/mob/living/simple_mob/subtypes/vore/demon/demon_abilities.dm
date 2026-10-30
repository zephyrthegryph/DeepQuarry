/mob/living/simple_mob/vore/demon/proc/blood_crawl_ready(datum/act/op/A)
	var/turf/T = get_turf(src)
	if(!T.CanPass(src,T) || loc != T)
		return span_warning("You can't use that here!")
	if((get_area(src).flags & PHASE_SHIELDED))
		return span_warning("This area is preventing you from phasing!")
	if(shift_state && shift_state == AB_SHIFT_ACTIVE)
		return span_warning("You can't do a shift while actively shifting!")
	if(!(locate_within(src.loc, /obj/effect/decal/cleanable/blood)))
		return span_warning("You need blood to shift between realities!")

/mob/living/simple_mob/vore/demon/proc/blood_crawl()
	var/turf/T = get_turf(src)

	forceMove(T)
	var/original_canmove = canmove
	status_set(STAT_STUNNED, 0)
	status_set(STAT_WEAKENED, 0)
	var/obj/buckled = src?.buckled_to()
	if(buckled)
		buckled.unbuckle_mob()
	var/mob/pulledby = src?.pulled_by_mob()
	if(pulledby)
		pulledby.stop_pulling()
	stop_pulling()
	set_canmove(FALSE)
	set_is_shifting(TRUE)

	//Shifting in
	if(shifted_out)
		set_shifted_out(FALSE)
		name = real_name
		for(var/obj/belly/B as anything in vore_organs)
			B.set_escapable(initial(B.escapable))

		set_alpha(initial(alpha))
		set_invisibility(initial(invisibility))
		see_invisible = initial(see_invisible)
		set_incorporeal_move(initial(incorporeal_move))
		set_density(initial(density))
		set_force_max_speed(living_rules_of_type(type).force_max_speed)

		//Cosmetics mostly
		flick("phasein",src)
		automatic_custom_emote(VISIBLE_MESSAGE,"phases in!")
		after(src, 3 SECONDS, PROC_REF(demon_phased_in), with = list(original_canmove, FALSE)) //The duration of the TP animation


	//Shifting out
	else
		set_shifted_out(TRUE)
		set_shift_state(AB_SHIFT_PASSIVE)
		automatic_custom_emote(VISIBLE_MESSAGE,"phases out!")
		set_real_name(name)
		name = "Something"
		fully_heal()

		for(var/obj/belly/B as anything in vore_organs)
			B.set_escapable(B_ESCAPABLE_NONE)

		flick("phaseout",src)
		after(src, 3 SECONDS, PROC_REF(demon_phased_out), with = list(original_canmove))

/mob/living/simple_mob/vore/demon/proc/blood_crawl_op(datum/act/op/A)
	blood_crawl()

/mob/living/simple_mob/vore/demon/proc/demonic_phase_shift_ready(datum/act/op/A)
	if(shift_state && shift_state == AB_SHIFT_PASSIVE)
		return span_warning("You can't do a shift while passively shifting!")
	if(shifted_out)
		return span_warning("You can't return to the physical world yet!")
	if(ELAPSED(src, last_shift, CLOCK_WORLD) < 600)
		return span_warning("You can't temporarily shift so soon! You need to wait [round(((last_shift+600)-world.time)/10)] second\s!")

/mob/living/simple_mob/vore/demon/proc/demonic_phase_shift()
	var/turf/T = get_turf(src)

	set_shift_state(AB_SHIFT_ACTIVE)
	forceMove(T)
	var/original_canmove = canmove
	status_set(STAT_STUNNED, 0)
	status_set(STAT_WEAKENED, 0)
	var/obj/buckled = src?.buckled_to()
	if(buckled)
		buckled.unbuckle_mob()
	var/mob/pulledby = src?.pulled_by_mob()
	if(pulledby)
		pulledby.stop_pulling()
	stop_pulling()
	set_canmove(FALSE)
	set_is_shifting(TRUE)

	set_shifted_out(TRUE)
	automatic_custom_emote(VISIBLE_MESSAGE,"phases out!")
	set_real_name(name)
	name = "Something"

	for(var/obj/belly/B as anything in vore_organs)
		B.set_escapable(B_ESCAPABLE_NONE)

	flick("phaseout",src)
	after(src, 3 SECONDS, PROC_REF(demon_phased_out), with = list(original_canmove))
	after(src, 33 SECONDS, PROC_REF(demon_shift_return))

/mob/living/simple_mob/vore/demon/proc/demonic_phase_shift_op(datum/act/op/A)
	demonic_phase_shift()

/// The temporary phase shift runs out: back into reality.
/mob/living/simple_mob/vore/demon/proc/demon_shift_return()
	set_shifted_out(FALSE)
	name = real_name
	for(var/obj/belly/B as anything in vore_organs)
		B.set_escapable(initial(B.escapable))

	set_alpha(initial(alpha))
	set_invisibility(initial(invisibility))
	see_invisible = initial(see_invisible)
	set_incorporeal_move(initial(incorporeal_move))
	set_density(initial(density))
	set_force_max_speed(living_rules_of_type(type).force_max_speed)
	var/original_canmove = canmove
	set_canmove(FALSE)
	set_is_shifting(TRUE)

	//Cosmetics mostly
	flick("phasein",src)
	automatic_custom_emote(VISIBLE_MESSAGE,"phases in!")
	after(src, 3 SECONDS, PROC_REF(demon_phased_in), with = list(original_canmove, TRUE)) //The duration of the TP animation

/mob/living/simple_mob/vore/demon/proc/demon_phased_out(original_canmove)
	set_invisibility(INVISIBILITY_LEVEL_TWO)
	see_invisible = INVISIBILITY_LEVEL_TWO
	set_alpha(127)

	set_is_shifting(FALSE)
	set_canmove(original_canmove)
	set_incorporeal_move(TRUE)
	set_density(FALSE)
	set_force_max_speed(TRUE)

	after(src, 30 SECONDS, PROC_REF(phase_shift_wears_off))
/// Phase-in animation done: maybe grab someone on arrival.
/mob/living/simple_mob/vore/demon/proc/demon_phased_in(original_canmove, from_temporary)
	set_is_shifting(FALSE)
	set_canmove(original_canmove)

	if(from_temporary)
		var/turf/NT = get_turf(src)
		if(!NT.CanPass(src,NT))
			for(var/direction in list(1,2,4,8,5,6,9,10))
				var/turf/L = get_step(NT, direction)
				if(L)
					if(L.CanPass(src,L))
						forceMove(L)
						break

	//Potential phase-in vore
	if(vore_prefs.can_be_drop_pred) //Toggleable in vore panel
		var/list/potentials = living_mobs(0)
		if(potentials.len)
			var/mob/living/target = pick(potentials)
			if(can_phase_vore(src, target))
				vore_selected_of(src).nom_atom(target)
				to_chat(target,span_vwarning("\The [src] phases in around you, [vore_selected_of(src).vore_verb]ing you into their [vore_selected_of(src).get_belly_name()]!"))

	// Do this after the potential vore, so we get the belly

	set_shift_state(AB_SHIFT_NONE)
	if(from_temporary)
		STAMP(src, last_shift, CLOCK_WORLD)


/mob/living/simple_mob/vore/demon/proc/blood_burst_ready(datum/act/op/A)
	if(shifted_out)
		return span_warning("You must be in the physical world to create blood!")
	if(ELAPSED(src, blood_spawn, CLOCK_WORLD) < 1500)
		return span_warning("You can't create blood so soon! You need to wait [round(((blood_spawn+1500)-world.time)/10)] second\s!")

/mob/living/simple_mob/vore/demon/proc/blood_burst()
	var/turf/T = get_turf(src)

	gibs(T)

	play_sfx(src.loc, SFX_EFFECTS_BLOBATTACK, volume = 50)

	STAMP(src, blood_spawn, CLOCK_WORLD)

	return

/mob/living/simple_mob/vore/demon/proc/blood_burst_op(datum/act/op/A)
	blood_burst()

/mob/living/simple_mob/vore/demon/proc/toggle_laugh()
	enable_autolaugh = !enable_autolaugh
	if(enable_autolaugh)
		to_chat(src,span_warning("Autolaugh has been toggled on"))
	else
		to_chat(src,span_warning("Autolaugh has been toggled off"))

/mob/living/simple_mob/vore/demon/proc/toggle_laugh_op(datum/act/op/A)
	toggle_laugh()

/mob/living/simple_mob/vore/demon/proc/manual_laugh()
	if(!enable_autolaugh) //yeah this is kinda sorta dirty but id rather use a bool over something else here to control this.
		enable_autolaugh = !enable_autolaugh
		laugh()
		enable_autolaugh = !enable_autolaugh
	else
		laugh()
	to_chat(src,span_warning("You laugh!")) //lets add some fluff response for clicking the feel good button.

/mob/living/simple_mob/vore/demon/proc/manual_laugh_op(datum/act/op/A)
	manual_laugh()

/mob/living/simple_mob/vore/demon/proc/grabbed_prey_ready(datum/act/op/A)
	var/obj/item/grab/G = src.get_active_hand()
	if(!istype(G))
		return span_warning("You must be grabbing a creature in your active hand to affect them.")
	var/mob/living/carbon/human/T = G?.grab_target()
	if(!istype(T))
		return span_warning("\The [T] is not able to be affected.")
	if(G.state != GRAB_NECK)
		return span_warning("You must have a tighter grip to affect this creature.")
	return null

/mob/living/simple_mob/vore/demon/proc/sizespell()
	var/obj/item/grab/G = src.get_active_hand()
	var/mob/living/carbon/human/T = G.grab_target()

	// The click cooldown and incapacitation are the old verb's silent rate limit: they read the click clock, which no requirement may track.
	if(!checkClickCooldown() || incapacitated(INCAPACITATION_ALL))
		return

	setClickCooldown(8)
	T.resize(size_amount)
	act_message(src, T, MSG_SELF(span_notice("You shrink %T%.")), MSG_OTHERS(span_warning("%U% shrinks %T%!")))

/mob/living/simple_mob/vore/demon
	var/size_amount = RESIZE_TINY //Adding a var to keep track of sizespell setting

/mob/living/simple_mob/vore/demon/proc/toggle_sizespell()
	open_request(src, /datum/prompt/number, PROC_REF(sizespell_chosen), answerer = src, title = "Set Size", question = "Put the desired size ([RESIZE_MINIMUM * 100]-[RESIZE_MAXIMUM * 100]%)", default = size_amount * 100, max_value = RESIZE_MAXIMUM * 100, min_value = RESIZE_MINIMUM * 100, timeout = 0) //Stolen from sizegun code

/mob/living/simple_mob/vore/demon/proc/toggle_sizespell_op(datum/act/op/A)
	toggle_sizespell()

/mob/living/simple_mob/vore/demon/proc/sizespell_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/size_select = A.answer.value
	if(!size_select)
		return
	size_amount = (size_select/100)
	to_chat(src,span_notice("Size spell set to [size_select]%")) //Telling the user the new amount

/mob/living/simple_mob/vore/demon/proc/demon_bite()
	var/obj/item/grab/G = src.get_active_hand()
	var/mob/living/carbon/human/T = G.grab_target()

	// The click cooldown and incapacitation are the old verb's silent rate limit: they read the click clock, which no requirement may track.
	if(!checkClickCooldown() || incapacitated(INCAPACITATION_ALL))
		return

	setClickCooldown(8)
	T.reagents.add_reagent(poison_type, poison_per_bite)
	act_message(src, T, MSG_SELF(span_notice("You bite %T%.")), MSG_OTHERS(span_warning("%U% bites %T%!")))

/mob/living/simple_mob/vore/demon/proc/phase_shift_wears_off()
	set_shifted_out(FALSE)
	name = real_name
	for(var/obj/belly/B as anything in vore_organs)
		B.set_escapable(initial(B.escapable))

	set_alpha(initial(alpha))
	set_invisibility(initial(invisibility))
	see_invisible = initial(see_invisible)
	set_incorporeal_move(initial(incorporeal_move))
	set_density(initial(density))
	set_force_max_speed(living_rules_of_type(type).force_max_speed)
	var/original_canmove = canmove
	set_canmove(FALSE)
	set_is_shifting(TRUE)

	//Cosmetics mostly
	flick("phasein",src)
	automatic_custom_emote(VISIBLE_MESSAGE,"phases in!")
	after(src, 3 SECONDS, PROC_REF(phase_in_lands), with = list(original_canmove)) //The duration of the TP animation

/// The end of the phase-in animation.
/mob/living/simple_mob/vore/demon/proc/phase_in_lands(original_canmove)
	set_is_shifting(FALSE)
	set_canmove(original_canmove)

	var/turf/NT = get_turf(src)

	if(!NT.CanPass(src,NT))
		for(var/direction in list(1,2,4,8,5,6,9,10))
			var/turf/L = get_step(NT, direction)
			if(L)
				if(L.CanPass(src,L))
					forceMove(L)
					break

	//Potential phase-in vore
	if(vore_prefs.can_be_drop_pred) //Toggleable in vore panel
		var/list/potentials = living_mobs(0)
		if(potentials.len)
			var/mob/living/target = pick(potentials)
			if(can_phase_vore(src, target))
				vore_selected_of(src).nom_atom(target)
				to_chat(target,span_vwarning("\The [src] phases in around you, [vore_selected_of(src).vore_verb]ing you into their [vore_selected_of(src).get_belly_name()]!"))

	// Do this after the potential vore, so we get the belly

	set_shift_state(AB_SHIFT_NONE)
	STAMP(src, last_shift, CLOCK_WORLD)

/mob/living/simple_mob/vore/demon/proc/sizespell_op(datum/act/op/A)
	sizespell()

/mob/living/simple_mob/vore/demon/proc/demon_bite_op(datum/act/op/A)
	demon_bite()
