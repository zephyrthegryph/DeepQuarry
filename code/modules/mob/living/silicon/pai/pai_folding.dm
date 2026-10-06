/mob/living/silicon/pai/verb/fold_out()
	set category = VERB_CAT_ABILITIES_PAI_COMMANDS
	set name = "Unfold Chassis"

	if(stat || has_status(STAT_SLEEPING) || has_status(STAT_PARALYZED) || has_status(STAT_WEAKENED))
		return

	if(loc != card)
		return

	// Lets not trap the pai forever. These are special cases we want to escape out of when in our card
	if(istype(loc.loc, /obj/item/pda))
		var/obj/item/pda/ourpda = loc.loc
		if(ourpda.pai == card)
			ourpda.pai.forceMove(ourpda.loc)
			own_take(ourpda, nameof(ourpda.pai))
			visible_message(span_warning("\The [card] ejects itself from \the [ourpda]."))
		return
	if(istype(loc.loc, /obj/item/storage/vore_egg))
		var/obj/item/storage/vore_egg/ouregg = loc.loc
		to_chat(src, span_notice("You craftily use your built in rumble function to break free of \the [ouregg]'s confines!"))
		ouregg.hatch(src)
		return

	if(is_folding_unsafe(loc.loc))
		to_chat(src, span_danger("It's not safe to unfold while inside a [loc.loc]!"))
		return

	if(card.projector != PP_FUNCTIONAL && card.emitter != PP_FUNCTIONAL)
		to_chat(src, span_warning("ERROR: System malfunction. Service required!"))

	if(!COOLDOWN_FINISHED(src, last_special))
		to_chat(src, span_warning("You can't unfold yet."))
		return

	COOLDOWN_START(src, last_special, 10 SECONDS)

	if(istype(card.loc, /obj/machinery)) // this statement allows pAIs stuck in a machine to eject themselves.
		var/obj/machinery/M = card.loc
		M.ejectpai()
	//I'm not sure how much of this is necessary, but I would rather avoid issues.
	if(istype(card.loc,/obj/item/rig_module))
		to_chat(src, span_filter_notice("There is no room to unfold inside this rig module. You're good and stuck."))
		return 0
	else if(istype(card.loc,/mob))
		var/mob/holder = card.loc
		if(ishuman(holder))
			var/mob/living/carbon/human/H = holder
			for(var/obj/item/organ/external/affecting in H.organs)
				if(card in affecting.implants)
					H.injure(INJURY_BLUNT, rand(30,50), affecting, src)
					rel_remove(affecting, nameof(affecting.implants), card)
					act_message(src, H, others = span_danger("%U% explodes out of %T%'s [affecting.name] in shower of gore!"))
					break
		holder.drop_from_inventory(card)
	else if(isbelly(card.loc)) // .
		to_chat(src, span_notice("There is no room to unfold in here. You're good and stuck.")) // .
		return 0 // .
	else if(istype(card.loc,/obj/item/pda))
		var/obj/item/pda/holder = card.loc
		own_take(holder, nameof(holder.pai))

	src.forceMove(card.loc)
	card.forceMove(src)
	card.screen_loc = null
	canmove = TRUE

	if(isturf(loc))
		var/turf/T = get_turf(src)
		if(istype(T)) T.visible_message(span_filter_notice(span_bold("[src]") + " folds outwards, expanding into a mobile form."))

	grant(src, granted_verb(/mob/living/silicon/pai/proc/pai_nom), src)
	grant(src, granted_verb(/mob/living/proc/vertical_nom), src)
	update_icon()

/mob/living/silicon/pai/verb/fold_up()
	set category = VERB_CAT_ABILITIES_PAI_COMMANDS
	set name = "Collapse Chassis"

	if(stat || has_status(STAT_SLEEPING) || has_status(STAT_PARALYZED) || has_status(STAT_WEAKENED))
		return

	if(src.loc == card)
		return

	if(!COOLDOWN_FINISHED(src, last_special))
		to_chat(src, span_warning("You can't fold up yet."))
		return

	close_up()

//I'm not sure how much of this is necessary, but I would rather avoid issues.
/mob/living/silicon/pai/proc/close_up(silent= FALSE)
	// A destroyed card has already cleared its incoming relation before pAI death runs.
	if(!card)
		return

	COOLDOWN_START(src, last_special, 10 SECONDS)

	if(loc == card)
		return

	// some snowflake locations where we really shouldn't fold up...
	if(is_folding_unsafe(loc))
		to_chat(src, span_danger("It's not safe to fold up while inside a [loc]!"))
		return

	release_vore_contents(FALSE)

	var/turf/T = get_turf(src)
	if(istype(T) && !silent) T.visible_message(span_filter_notice(span_bold("[src]") + " neatly folds inwards, compacting down to a rectangular card."))

	stop_pulling()

	//stop resting
	set_resting(0)

	// If we are being held, handle removing our holder from their inv.
	var/obj/item/holder/our_holder = loc
	if(istype(our_holder))
		var/turf/drop_turf = get_turf(our_holder)
		var/mob/living/M = our_holder.loc
		if(istype(M))
			M.drop_from_inventory(our_holder)
		src.forceMove(card)
		card.forceMove(drop_turf)

	if(isbelly(loc))	//If in tumby, when fold up, card go into tumby
		var/obj/belly/B = loc
		src.forceMove(card)
		card.forceMove(B)

	if(isdisposalpacket(loc))
		var/obj/structure/disposalholder/hold = loc
		src.forceMove(card)
		card.forceMove(hold)

	else				//Otherwise go on floor
		card.forceMove(get_turf(src))
		src.forceMove(card)

	canmove = 1
	set_resting(0)
	icon_state = SSpai.chassis_data(chassis_name).sprite_icon_state
	if(isopenspace(card.loc))
		fall()
	revoke(src, granted_verb(/mob/living/silicon/pai/proc/pai_nom), src)
	revoke(src, granted_verb(/mob/living/proc/vertical_nom), src)

/mob/living/silicon/pai/proc/is_folding_unsafe(check_location)
	return isbelly(check_location) || istype(check_location, /obj/machinery) || istype(check_location, /obj/item/storage/vore_egg) || istype(check_location, /obj/item/pda)
