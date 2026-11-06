//////Paranormal Investigator stuff

/obj/item/entrepreneur/emf
	name = "EMF scanner"
	desc = "A handheld device used for detecting disturbances to electromagnetic fields."
	icon = 'icons/obj/entrepreneur.dmi'
	icon_state = "emf"
	var/emf = 5
	///If our scanner will accurately detect ghosts or not.
	var/advanced = FALSE
	///How far our we search. 0 = own turf.
	var/detection_range = 0

	///How often we can use the EMF actively.
	COOLDOWN_DECLARE(scan_cooldown)

/// TRUE while it is carried by a mob: the slow reading step runs only then.
/obj/item/entrepreneur/emf/var/tmp/reading = FALSE

/obj/item/entrepreneur/emf/examine(mob/user)
	. = ..()
	switch(emf)
		if(-1000 to 20)
			. += span_info("The EMF reader is very low, reading [emf]mG.")
		if(20 to 40)
			. += span_info("The EMF reader is low, reading [emf]mG.")
		if(40 to 60)
			. += span_info(span_red("The EMF reader is reading moderate interference, reading [emf]mG."))
		if(60 to 80)
			. += span_info(span_red("The EMF reader is reading high interference, reading [emf]mG."))
		if(80 to 1000)
			. += span_info(span_red("The EMF reader is reading extremely high interference, reading [emf]mG."))

/// Senses every 2 s while carried; set down, the work stops.
/obj/item/entrepreneur/emf/proc/emf_step(datum/act/A)
	if(!ismob(loc))
		set_reading(FALSE)
		return
	search_for_ghosts()

CAPABILITIES(/obj/item/entrepreneur/emf)
	every(2 SECONDS, then(PROC_REF(emf_step)), when = nameof(reading))
	op("scan", in_hand(), label("Read EMF scanner"), then(PROC_REF(emf_scan_requested)))
	rolls(nameof(emf), range_of(1, 100))

/obj/item/entrepreneur/emf/proc/emf_scan_requested(datum/act/op/A)
	var/mob/user = A.actor
	if(COOLDOWN_FINISHED(src, scan_cooldown))
		search_for_ghosts(user)
	else
		to_chat(user, span_warning("Your EMF scanner is recharging. The current reading is [emf]mG."))
	return OP_OK

/obj/item/entrepreneur/emf/proc/search_for_ghosts(mob/user)
	var/turf/our_turf = get_turf(src)
	if(!our_turf)
		return

	///How many ghosts are around us.
	var/ghosts_present = 0
	///How much we'll increase/decrease the EMF reading.
	var/emf_change = 0

	//Loop for the 'advanced' emfs, which detect actual ghosts/phasers.
	if(advanced)
		for(var/mob/entity in range(detection_range, our_turf))
			if(isobserver(entity))
				var/mob/observer/dead/ghost = entity
				if(ghost?.following_target() || !ghost.interact_with_world || ghost.admin_ghosted) //Ghosts orbiting us or someone else, or have opted out of interactions.
					continue
				ghosts_present++
			if(entity.is_incorporeal())
				ghosts_present++

	if(emf >= 100)
		set_emf(100)
	if(emf <= 20)
		set_emf(20)

	if(ghosts_present)
		if(advanced)
			emf_change = rand(3 * ghosts_present, 10 * ghosts_present)
		else
			emf_change = rand(-15,20) //Trend upwards but not by enough to prove ghosts actually exist
	else
		if(advanced)
			emf_change = rand(-5, -1)
		else
			emf_change = rand(-20,15) //Trend downwards
	set_emf((emf + emf_change))
	if(user)
		to_chat(user, span_notice("You update the EMF scanner and check the reading. It reads [emf]mG!"))
		COOLDOWN_START(src, scan_cooldown, 5 SECONDS)

/obj/item/entrepreneur/emf/proc/appearance_level()
	if(emf <= 20)
		return 0
	if(emf <= 40)
		return 20
	if(emf <= 60)
		return 40
	if(emf <= 80)
		return 60
	return 80

/// The look (the draw sweep: from its template).
/obj/item/entrepreneur/emf/draw(datum/look/look)
	..()
	look.state("emf-[appearance_level()]")

/// Senses while carried (picking it up starts it); set down, it sleeps.
/obj/item/entrepreneur/emf/equipped(mob/user, slot)
	. = ..()
	set_reading(TRUE)
