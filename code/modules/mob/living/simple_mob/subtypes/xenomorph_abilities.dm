/mob/living/simple_mob/xeno_ch/proc/xeno_build_done(choice, targetLoc)
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

/mob/living/simple_mob/xeno_ch/proc/xeno_build()
	set name = "Build Resin Structure"
	set desc = "Build a xenomorph resin structure."
	set category = VERB_CAT_ABILITIES_XENO

	var/list/options = list("Resin Door","Resin Membrane","Nest","Resin Wall","Weed Node")
	for(var/option in options)
		LAZYSET(options, option, image('icons/mob/xeno_screen.dmi', option))
	open_request(src, /datum/prompt/choice, PROC_REF(xeno_build_chosen), answerer = src, choices = options, anchor = src, radius = 60, radial = TRUE, autopick_single_option = TRUE, timeout = 0)

/// Radial answer for xeno_build(): start shaping the picked structure.
/mob/living/simple_mob/xeno_ch/proc/xeno_build_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/choice = A.answer.value
	if(!choice || QDELETED(src) || src.incapacitated())
		return

	var/targetLoc = get_step(src, dir)

	if(iswall(targetLoc))
		targetLoc = get_turf(src)

	task_timed(src, xeno_build_time, target = src, receiver = src, on_done = PROC_REF(xeno_build_done), done_args = list(choice, targetLoc))




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
	parent_xeno.xeno_build()


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

