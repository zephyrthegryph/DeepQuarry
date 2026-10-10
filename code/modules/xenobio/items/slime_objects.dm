// Slime cube lives here.  Makes Prometheans.
/obj/item/slime_cube/get_mechanics_info(list/additional_information)
	return ..(list("A ghost is needed to become the Promethean, similar to a positronic brain.") + additional_information)

/obj/item/slime_cube
	name = "slimy monkey cube"
	desc = "Wonder what might come out of this."
	icon = 'icons/mob/slime2.dmi'
	icon_state = "slime cube"
	var/searching = 0

CAPABILITIES(/obj/item/slime_cube)
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/slime_cube/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(!searching)
		to_chat(user, span_warning("You stare at the slimy cube, watching as some activity occurs."))
		icon_state = "slime cube active"
		searching = 1
		request_player()
		after(src, 60 SECONDS, PROC_REF(reset_search))
	return TRUE

// Sometime down the road it would be great to make all of these 'ask ghosts if they want to be X' procs into a generic datum.
/obj/item/slime_cube/proc/request_player()
	for(var/mob/observer/dead/O in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(!O.MayRespawn())
			continue
		if(O.client)
			if(O.client.prefs.read_preference(/datum/preference/numeric/human/be_special) & BE_ALIEN) // migrated
				question(O.client)

/obj/item/slime_cube/proc/question(client/C)
	if(!C || QDELETED(C.mob))
		return
	var/datum/slime_cube_invitation_review/review = new
	review.client_ckey = C.ckey
	rel_set(review, nameof(review.actor), C.mob)
	rel_set(review, nameof(review.cube), src)
	review.run_step()

/datum/slime_cube_invitation_review
	var/tmp/mob/actor
	var/tmp/obj/item/slime_cube/cube
	var/client_ckey
	var/stage = 0
	var/first_answer
	var/confirmation

CAPABILITIES(/datum/slime_cube_invitation_review)
	ref_one(nameof(actor), /mob)
	ref_one(nameof(cube), /obj/item/slime_cube)

/datum/slime_cube_invitation_review/proc/refusal()
	if(QDELETED(actor) || QDELETED(cube) || !GLOB.directory[client_ckey])
		return "The original invitation is no longer available."

/datum/slime_cube_invitation_review/proc/run_step()
	var/datum/result/result = safe_call(PROC_REF(replay))
	if(!result.ok)
		stack_trace("Slime cube invitation continuation: [result.error]")
	if(stage > 0 && !QDELETED(cube))
		SStgui.update_uis(cube)
	if(!result.ok || result.value != TRUE)
		retire()

/datum/slime_cube_invitation_review/proc/answered(datum/act/request/context)
	if(!context.answer)
		retire()
		return
	if(stage == 0)
		first_answer = context.request.value
	else
		confirmation = context.request.value
	stage++
	run_step()

/datum/slime_cube_invitation_review/proc/replay()
	var/client/C = GLOB.directory[client_ckey]
	if(!C || QDELETED(C.mob) || QDELETED(cube))
		return
	rel_set(src, nameof(actor), C.mob)
	if(stage == 0)
		open_request(src, /datum/prompt/choice/slime_cube_invitation, PROC_REF(answered), answerer = actor)
		return TRUE
	var/response = first_answer
	if(response == "Yes")
		if(stage == 1)
			open_request(src, /datum/prompt/choice/slime_cube_invitation/confirm, PROC_REF(answered), answerer = actor)
			return TRUE
		response = confirmation
	if(!C || 2 == cube.searching)
		return // Preserve responses issued after a brain has been located.
	if(response == "Yes")
		cube.transfer_personality(C.mob)
	else if(response == "Never for this round")
		C.prefs.update_preference_by_type(/datum/preference/numeric/human/be_special, C.prefs.read_preference(/datum/preference/numeric/human/be_special) ^ BE_ALIEN)

/datum/slime_cube_invitation_review/proc/retire()
	spent(src)

/datum/prompt/choice/slime_cube_invitation
	title = "Promethean request"
	question = "Someone is requesting a soul for a promethean. Would you like to play as one?"
	choices = list("Yes", "No", "Never for this round")
	buttons = TRUE
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/choice/slime_cube_invitation/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/slime_cube_invitation_review/review = owner
	return review.refusal()

/datum/prompt/choice/slime_cube_invitation/confirm
	question = "Are you sure you want to play as a promethean?"
	choices = list("Yes", "No")

/obj/item/slime_cube/proc/reset_search() //We give the players sixty seconds to decide, then reset the timer.
	icon_state = "slime cube"
	if(searching == 1)
		searching = 0
		var/turf/T = get_turf_or_move(src.loc)
		for (var/mob/M in viewers(T))
			M.show_message(span_warning("The activity in the cube dies down. Maybe it will spark another time."))

/obj/item/slime_cube/proc/transfer_personality(mob/candidate)
	announce_ghost_joinleave(candidate, 0, "They are a promethean now.")
	src.searching = 2
	var/mob/living/carbon/human/S = new(get_turf(src))
	S.client = candidate.client
	to_chat(S, span_infoplain(span_bold("You are a promethean, brought into existence on [station_name()].")))
	S.mind.assigned_role = JOB_PROMETHEAN
	S.set_species("Promethean")
	S.shapeshifter_set_colour("#2398FF")
	visible_message(span_warning("The monkey cube suddenly takes the shape of a humanoid!"))
	var/newname = rerun_ask(S, "k62", PROC_REF(transfer_personality), args, /datum/prompt/text, question = "You are a Promethean. Would you like to change your name to something else?", title = "Name change", max_len = MAX_NAME_LEN, name_text = ((MAX_NAME_LEN) <= MAX_NAME_LEN))
	if(isnull(newname))
		return
	if(newname)
		S.real_name = newname
		S.name = S.real_name
		S.dna.real_name = newname
	if(S.mind)
		S.mind.name = S.name
	consume(src, candidate)

// More or less functionally identical to the telecrystal tele.
/obj/item/slime_crystal/get_mechanics_info(list/additional_information)
	return ..(list("Teleports its user to a mostly 'safe' tile, consuming the crystal. Throwing it at someone or attacking them with it teleports them instead.") + additional_information)

/obj/item/slime_crystal
	name = "lesser slime cystal"
	desc = "A small, gooy crystal."
	icon = 'icons/obj/objects.dmi'
	icon_state = "slime_crystal_small"
	w_class = ITEMSIZE_TINY
	force = 1 //Needs a token force to ensure you can attack because for some reason you can't attack with 0 force things

/obj/item/slime_crystal/apply_hit_effect(mob/living/target, mob/living/user, hit_zone)
	if(loc?.release_refusal(src, user))
		return
	act_message(target, src, others = span_warning("%U% has been teleported with %T% by \the [user]!"))
	safe_blink(target, 14)
	consume(src, user)

CAPABILITIES(/obj/item/slime_crystal)
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/slime_crystal/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(loc?.release_refusal(src, user))
		return FALSE
	act_message(user, src, others = span_warning("%U% teleports themselves with %T%!"))
	safe_blink(user, 14)
	consume(src, user)
	return TRUE

/obj/item/slime_crystal/throw_impact(atom/movable/AM)
	if(!istype(AM))
		return

	if(AM.anchored)
		return
	if(loc?.release_refusal(src))
		return

	AM.visible_message(span_warning("\The [AM] has been teleported with \the [src]!"))
	safe_blink(AM, 14)
	consume(src)

/obj/item/disposable_teleporter/slime
	name = "greater slime crystal"
	desc = "A larger, gooier crystal."
	icon = 'icons/obj/objects.dmi'
	icon_state = "slime_crystal_large"
	uses = 1
	w_class = ITEMSIZE_SMALL

// Very filling food.
/obj/item/reagent_containers/food/snacks/slime
	bitesize = 5
	name = "slimy clump"
	desc = "A glob of slime that is thick as honey.  For the brave " + JOB_XENOBIOLOGIST + "."
	icon_state = "honeycomb"
	filling_color = "#FFBB00"
	center_of_mass_x = 17
	center_of_mass_y = 10
	nutriment_amt = 25 // Very filling.
	nutriment_desc = list("slime" = 10, "sweetness" = 10, REAGENT_ID_BLISS = 5)

//Flashlight

/obj/item/flashlight/slime
	gender = PLURAL
	name = "glowing slime extract"
	desc = "A slimy ball that appears to be glowing from bioluminesence."
	icon = 'icons/obj/lighting.dmi'
	icon_state = "floor1" //not a slime extract sprite but... something close enough!
	item_state = "slime"
	light_color = "#FFF423"
	w_class = ITEMSIZE_TINY
	light_range = 6
	on = 1 //Bio-luminesence has one setting, on.
	power_use = 0
	light_system = STATIC_LIGHT
	special_handling = TRUE

/obj/item/flashlight/slime/Initialize(mapload)
	. = ..()
	set_light(light_range, light_power, light_color)

/obj/item/flashlight/slime/update_brightness()
	return

//Radiation Emitter

/obj/item/slime_irradiator
	name = "glowing slime extract"
	desc = "A slimy ball that appears to be glowing from bioluminesence."
	icon = 'icons/mob/slimes_vr.dmi'
	icon_state = "irradiator"
	light_color = "#00FF00"
	light_power = 0.4
	light_range = 2
	light_on = TRUE // lit from the start: static light vars are applied when it materializes (on_materialize() -> update_light())
	w_class = ITEMSIZE_TINY
	COOLDOWN_DECLARE(event_cooldown)
	/// Mutex to prevent infinite recursion when propagating radiation pulses
	var/active = null

CAPABILITIES(/obj/item/slime_irradiator)
	every(2 SECONDS, then(PROC_REF(slime_irradiator_step)))

/// Radiates only while a mob is close enough to be affected; with none near, the run does nothing.
/obj/item/slime_irradiator/proc/slime_irradiator_step(datum/act/timer/A)
	if(!mob_near(world.view))
		return
	radiate()

/obj/item/slime_irradiator/proc/radiate()
	if(active)
		return
	if(!COOLDOWN_FINISHED(src, event_cooldown))
		return
	active = TRUE
	radiation_pulse(
		src,
		max_range = 5,
		threshold = RAD_MEDIUM_INSULATION,
		chance = URANIUM_IRRADIATION_CHANCE,
		minimum_exposure_time = URANIUM_RADIATION_MINIMUM_EXPOSURE_TIME,
		strength = 25
	)
	COOLDOWN_START(src, event_cooldown, 1.5 SECONDS)
	active = FALSE

//BS Pouch
/obj/item/storage/backpack/holding/slime
	name = "bluespace slime pouch"
	desc = "A slimy pouch that opens into a localized pocket of bluespace."
	icon_state = "slimepouch"

//Slime Chems

/datum/reagent/myelamine/slime
	name = "Agent A"
	id = REAGENT_ID_SLIMEBLEEDFIXER
	description = "A slimy liquid which appears to rapidly clot internal hemorrhages by increasing the effectiveness of platelets at low quantities.  Toxic in high quantities."
	taste_description = "slime"
	overdose = 5

/datum/reagent/osteodaxon/slime
	name = "Agent B"
	id = REAGENT_ID_SLIMEBONEFIXER
	description = "A slimy liquid which can be used to heal bone fractures at low quantities.  Toxic in high quantities."
	taste_description = "slime"
	overdose = 5

/datum/reagent/peridaxon/slime
	name = "Agent C"
	id = REAGENT_ID_SLIMEORGANFIXER
	description = "A slimy liquid which is used to encourage recovery of internal organs and nervous systems in low quantities.  Toxic in high quantities."
	taste_description = "slime"
	overdose = 5

/datum/reagent/nutriment/glucose/slime
	name = "Slime Goop"
	id = "slime_goop"
	description = "A slimy liquid, with very compelling smell. Extremely nutritious."
	color = "#FABA3A"
	nutriment_factor = 30
	taste_description = "slimy nectar"
	wiki_flag = WIKI_FOOD|WIKI_SPOILER
