/// The structures the xeno can shape, each with its radial icon.
/mob/living/simple_mob/xeno_ch/proc/xeno_build_choices(datum/act/op/A)
	var/list/options = list("Resin Door", "Resin Membrane", "Nest", "Resin Wall", "Weed Node")
	for(var/option in options)
		LAZYSET(options, option, image('icons/mob/xeno_screen.dmi', option))
	return options

/// The time it takes to shape a structure.
/mob/living/simple_mob/xeno_ch/proc/xeno_build_wait(datum/act/A)
	return xeno_build_time

/// The end of the "xeno_build" op: the picked structure stands in front of the xeno (on its own tile against a wall).
/mob/living/simple_mob/xeno_ch/proc/xeno_build_done(datum/act/op/A)
	var/choice = A.step_value("choice")
	if(!choice)
		return
	var/targetLoc = get_step(src, dir)
	if(iswall(targetLoc))
		targetLoc = get_turf(src)

	var/obj/O
	switch(choice)
		if("Resin Door")
			O = new /obj/structure/simple_door/resin(targetLoc)

		if("Resin Membrane")
			O = new /obj/structure/alien/membrane(targetLoc)

		if("Nest")
			O = new /obj/structure/bed/nest(targetLoc)

		if("Resin Wall")
			O = new /obj/structure/alien/wall(targetLoc)

		if("Weed Node")
			O = new /obj/effect/alien/weeds/node(targetLoc)

	if(O)
		act_message(src, null, MSG_SELF(span_alium("You shape a [choice].")), MSG_OTHERS(span_boldwarning("%U% vomits up a thick purple substance and begins to shape it!")))
		O.color = "#321D37"
		play_sfx(src, SFX_EFFECTS_BLOBATTACK, volume = 40)



/////
/////
// DATUM actions for xeno buttons
/////
/////



/datum/action/innate/xeno_ch
	check_flags = AB_CHECK_RESTRAINED | AB_CHECK_STUNNED | AB_CHECK_CONSCIOUS
	button_icon = 'icons/mob/xeno_screen.dmi'
	var/mob/living/simple_mob/xeno_ch/parent_xeno


/datum/action/innate/xeno_ch/Grant(mob/living/L)
	if(L)
		rel_set(src, nameof(parent_xeno), L)
	..()

/datum/action/innate/xeno_ch/xeno_build
	name = "Build resin structures"
	button_icon_state = "Nest"

/datum/action/innate/xeno_ch/xeno_build/Activate()
	perform_op(parent_xeno, parent_xeno, "xeno_build", null, ORIGIN_VERB, AUTH_PHYSICAL)


/datum/action/innate/xeno_ch/xeno_neuro
	name = "Spit neurotoxin"
	button_icon_state = "Neuro Spit"

/datum/action/innate/xeno_ch/xeno_neuro/Activate()
	parent_xeno.neurotoxin()


/datum/action/innate/xeno_ch/xeno_acidspit
	name = "Spit acid"
	button_icon_state = "Acid Spit"

/datum/action/innate/xeno_ch/xeno_acidspit/Activate()
	parent_xeno.acidspit()


/datum/action/innate/xeno_ch/xeno_corrode
	name = "Corrode Object"
	button_icon_state = "Acid"

/datum/action/innate/xeno_ch/xeno_corrode/Activate()
	parent_xeno.corrosive_acid()


/datum/action/innate/xeno_ch/xeno_pounce
	name = "Pounce"
	button_icon_state = "Pounce"

/datum/action/innate/xeno_ch/xeno_pounce/Activate()
	parent_xeno.pounce_toggle()

/datum/action/innate/xeno_ch/xeno_spin
	name = "Spin"
	button_icon_state = "Spin"

/datum/action/innate/xeno_ch/xeno_spin/Activate()
	parent_xeno.speen()


/mob/living/simple_mob/xeno_ch/proc/grantallactions()
	build_action.Grant(src)
	neurotox_action.Grant(src)
	acidspit_action.Grant(src)
	corrode_action.Grant(src)
	pounce_action.Grant(src)
	spin_action.Grant(src)

