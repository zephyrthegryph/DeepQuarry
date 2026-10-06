// These should all be procs, you can add them to humans/subspecies by
// species.dm's inherent_verbs ~ Z

/mob/living/carbon/human/proc/tie_hair()
	set name = "Tie Hair"
	set desc = "Style your hair."
	set category = VERB_CAT_IC_GAME

	if(incapacitated())
		to_chat(src, span_warning("You can't mess with your hair right now!"))
		return

	if(h_style)
		var/datum/sprite_accessory/hair/hair_style = GLOB.hair_styles_list[h_style]
		if(!(hair_style.flags & HAIR_TIEABLE))
			to_chat(src, span_warning("Your hair isn't long enough to tie."))
			return
		var/list/datum/sprite_accessory/hair/valid_hairstyles = list()
		for(var/hair_string in GLOB.hair_styles_list)
			var/datum/sprite_accessory/hair/test = GLOB.hair_styles_list[hair_string]
			if(test.flags & HAIR_TIEABLE)
				valid_hairstyles.Add(hair_string)
		open_request(src, /datum/prompt/choice, PROC_REF(tie_hair_chosen), answerer = src, title = "Your hairstyle", question = "Select a new hairstyle", choices = valid_hairstyles, ask_flags = ASK_CAPABLE, timeout = 0)

/mob/living/carbon/human/proc/tie_hair_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/selected_string = A.answer.value
	if(selected_string && h_style != selected_string)
		h_style = selected_string
		regenerate_icons()
		act_message(src, null, others = span_notice("%U% pauses a moment to style their hair."))
	else
		to_chat(src, span_notice("You're already using that style."))

/mob/living/carbon/human/proc/tackle()
	set category = VERB_CAT_ABILITIES_GENERAL
	set name = "Tackle"
	set desc = "Tackle someone down."

	if(!COOLDOWN_FINISHED(src, last_special))
		return

	if(stat || has_status(STAT_PARALYZED) || has_status(STAT_STUNNED) || has_status(STAT_WEAKENED) || lying || restrained() || src?.buckled_to())
		to_chat(src, span_notice("You cannot tackle someone in your current state."))
		return

	var/list/choices = list()
	for(var/mob/living/M in view(1,src))
		if(!istype(M,/mob/living/silicon) && Adjacent(M))
			choices += M
	choices -= src

	open_request(src, /datum/prompt/choice/tackle, PROC_REF(tackle_target_chosen), answerer = src, choices = choices)

/// Re-checked on the answer: conscious, next to the target, off cooldown and able to tackle.
/datum/prompt/choice/tackle
	title = "Target Choice"
	question = "Who do you wish to tackle?"
	timeout = 0
	ask_flags = ASK_CONSCIOUS

/datum/prompt/choice/tackle/recheck_extra()
	if(isnull(value))
		return
	var/mob/living/selected = value
	if(!istype(selected) || QDELETED(selected))
		return "gone"
	var/mob/living/carbon/human/H = answerer
	if(!H.Adjacent(selected) || !COOLDOWN_FINISHED(H, last_special))
		return "can't reach"
	if(H.stat || H.has_status(STAT_PARALYZED) || H.has_status(STAT_STUNNED) || H.has_status(STAT_WEAKENED) || H.lying || H.restrained() || H.buckled_to())
		return "not able to"
	return null

/mob/living/carbon/human/proc/tackle_target_chosen(datum/act/request/A)
	if(!A.answer)
		var/datum/request/request = A.request
		if(request.outcome == REQ_CANCELLED && !isnull(request.value) && request.last_error == "not able to")
			to_chat(request.answerer, span_notice("You cannot tackle in your current state."))
		return
	return tackle_target_apply(A)

/mob/living/carbon/human/proc/tackle_target_apply(datum/act/request/A)
	var/mob/living/T = A.answer.value

	COOLDOWN_START(src, last_special, 5 SECONDS)

	var/failed
	if(prob(75))
		T.status_at_least(STAT_WEAKENED, rand(0.5,3))
	else
		failed = 1

	play_sfx(src, SFX_WEAPONS_PIERCE)
	if(failed)
		src.status_at_least(STAT_WEAKENED, rand(2,4))

	for(var/mob/O in viewers(src, null))
		if ((O.client && !( O.blinded )))
			O.show_message(span_warning(span_red(span_bold("[src] [failed ? "tried to tackle" : "has tackled"] down [T]!"))), 1)

/mob/living/carbon/human/proc/commune()
	set category = VERB_CAT_ABILITIES_GENERAL
	set name = "Commune with creature"
	set desc = "Send a telepathic message to an unlucky recipient."

	open_request(src, /datum/prompt/choice, PROC_REF(commune_target_chosen), answerer = src, question = "Select a creature!", title = "Speak to creature", choices = getmobs(), timeout = 0)

/mob/living/carbon/human/proc/commune_target_chosen(datum/act/request/A)
	if(!A.answer)
		return
	return apply_commune_target_chosen(A)

/mob/living/carbon/human/proc/apply_commune_target_chosen(datum/act/request/A)
	var/datum/prompt/choice/ask = A.request
	var/mob/M = ask.choices[A.answer.value]
	if(!M)
		return
	open_request(src, /datum/prompt/text/telepathy, PROC_REF(commune_answered), answerer = src, question = "What would you like to say?", title = "Speak to creature", recipient = M, recipient_expected = !isnull(M))

/mob/living/carbon/human/proc/commune_answered(datum/act/request/A)
	if(!A.answer)
		return
	return apply_commune_answered(A)

/mob/living/carbon/human/proc/apply_commune_answered(datum/act/request/A)
	var/datum/prompt/text/telepathy/ask = A.request
	var/text = A.answer.value
	var/mob/M = ask.recipient

	if(isobserver(M) || M.stat == DEAD)
		to_chat(src, span_filter_notice("Not even a [src.species.name] can speak to the dead."))
		return

	log_talk("(COMMUNE to [key_name(M)]) [text]", LOG_SAY)

	to_chat(M, span_filter_say("[span_blue("Like lead slabs crashing into the ocean, alien thoughts drop into your mind: [text]")]"))
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		if(H.species.name == src.species.name)
			return
		to_chat(H, span_filter_notice("[span_red("Your nose begins to bleed...")]"))
		H.drip(1)

/mob/living/carbon/human/proc/psychic_whisper(mob/M as mob in oview())
	set name = "Psychic Whisper"
	set desc = "Whisper silently to someone over a distance."
	set category = VERB_CAT_ABILITIES_GENERAL

	open_request(src, /datum/prompt/text/telepathy, PROC_REF(psychic_whisper_entered), answerer = src, title = "Psychic Whisper", recipient = M, recipient_expected = !isnull(M))

/mob/living/carbon/human/proc/psychic_whisper_entered(datum/act/request/A)
	if(!A.answer)
		return
	return apply_psychic_whisper_entered(A)

/mob/living/carbon/human/proc/apply_psychic_whisper_entered(datum/act/request/A)
	var/datum/prompt/text/telepathy/ask = A.request
	var/mob/M = ask.recipient
	var/msg = A.answer.value
	log_talk("(PWHISPER to [key_name(M)]) [msg]", LOG_WHISPER)
	to_chat(M, span_filter_say("[span_green("You hear a strange, alien voice in your head... <i>[msg]</i>")]"))
	to_chat(src, span_filter_say("[span_green("You said: \"[msg]\" to [M]")]"))

/mob/living/carbon/human/proc/diona_split_nymph()
	set name = "Split"
	set desc = "Split your humanoid form into its constituent nymphs."
	set category = VERB_CAT_ABILITIES_DIONA
	diona_split_into_nymphs(5)	// Separate proc to void argments being supplied when used as a verb

/mob/living/carbon/human/proc/diona_split_into_nymphs(number_of_resulting_nymphs)
	var/turf/T = get_turf(src)

	var/mob/living/carbon/alien/diona/S = new(T)
	S.set_dir(dir)
	transfer_languages(src, S)

	if(mind)
		mind.transfer_to(S)

	message_admins("\The [src] has split into nymphs; player now controls [key_name_admin(S)]")
	log_admin("\The [src] has split into nymphs; player now controls [key_name(S)]")

	var/nymphs = 1

	for(var/mob/living/carbon/alien/diona/D in contents_of(src))
		nymphs++
		D.forceMove(T)
		transfer_languages(src, D, WHITELISTED|RESTRICTED)
		D.set_dir(pick(NORTH, SOUTH, EAST, WEST))

	if(nymphs < number_of_resulting_nymphs)
		for(var/i in nymphs to (number_of_resulting_nymphs - 1))
			var/mob/M = new /mob/living/carbon/alien/diona(T)
			transfer_languages(src, M, WHITELISTED|RESTRICTED)
			M.set_dir(pick(NORTH, SOUTH, EAST, WEST))


	for(var/obj/item/W in contents_of(src))
		drop_from_inventory(W)

	var/obj/item/organ/external/Chest = organs_by_name[BP_TORSO]

	if(Chest.robotic >= 2)
		act_message(src, null, others = span_warning("%U% shudders slightly, then ejects a cluster of nymphs with a wet slithering noise."))
		species.remove_inherent_verbs(src) // the diona species granted split and regenerate
		proto_set(src, nameof(species), GLOB.all_species[SPECIES_HUMAN]) // This is hard-set to default the body to a normal FBP, without changing anything.

		// Bust it
		src.death()

		for(var/obj/item/organ/internal/diona/Org in internal_organ_list()) // Remove Nymph organs. (a fresh list from the organ slots)
			ended_with(Org, src)

		for(var/obj/item/organ/external/E in organs.Copy()) // Just fall apart.
			E.droplimb(TRUE)

	else
		act_message(src, null, others = span_warning("%U% quivers slightly, then splits apart with a wet slithering noise."))
		replaced_by(src)

/mob/living/carbon/human/proc/self_diagnostics()
	set name = "Self-Diagnostics"
	set desc = "Run an internal self-diagnostic to check for damage."
	set category = VERB_CAT_ABILITIES_GENERAL

	if(stat == DEAD) return

	to_chat(src, span_notice("Performing self-diagnostic, please wait..."))

	after(src, 5 SECONDS, PROC_REF(self_diagnostic_report))

/mob/living/carbon/human/proc/self_diagnostic_report()
	var/output = span_filter_notice("Self-Diagnostic Results:\n")

	output += "Internal Temperature: [convert_k2c(body_temperature())] Degrees Celsius\n"

	if(HAS_SYNTHETIC_BIOLOGY(src))
		output += "Current Battery Charge: [nutrition]\n"

		var/toxDam = injury_load(INJURY_CATEGORY_TOXIC)
		if(toxDam)
			output += "System Instability: " + span_warning("[toxDam > 25 ? "Severe" : "Moderate"]") + ". Seek charging station for cleanup.\n"
		else
			output += "System Instability: " + span_green("OK") + "\n"

	for(var/obj/item/organ/external/EO in organs)
		if(EO.is_assisted())
			if(EO.get_trauma() || EO.get_burn())
				output += "[EO.name] - " + span_warning("[EO.get_burn() + EO.get_trauma() > EO.min_broken_damage ? "Heavy Damage" : "Light Damage"]") + "\n" // Makes robotic limb damage scalable
			else
				output += "[EO.name] - " + span_green("OK") + "\n"

	for(var/obj/item/organ/IO in internal_organ_list())
		if(IO.is_assisted())
			if(IO.damage)
				output += "[IO.name] - " + span_warning("[IO.damage > 10 ? "Heavy Damage" : "Light Damage"]") + "\n"
			else
				output += "[IO.name] - " + span_green("OK") + "\n"
	output = span_notice(output)

	to_chat(src,output)

/mob/living/carbon/human
	var/next_sonar_ping = 0

/mob/living/carbon/human/proc/sonar_ping()
	set name = "Listen In"
	set desc = "Allows you to listen in to movement and noises around you."
	set category = VERB_CAT_ABILITIES_GENERAL

	if(incapacitated())
		to_chat(src, span_warning("You need to recover before you can use this ability."))
		return
	if(!COOLDOWN_FINISHED(src, next_sonar_ping))
		to_chat(src, span_warning("You need another moment to focus."))
		return
	if(is_deaf() || is_below_sound_pressure(get_turf(src)))
		to_chat(src, span_warning("You are for all intents and purposes currently deaf!"))
		return
	next_sonar_ping += 10 SECONDS
	var/heard_something = FALSE
	to_chat(src, span_notice("You take a moment to listen in to your environment..."))
	for(var/mob/living/L in range(client.view, src))
		var/turf/T = get_turf(L)
		if(!T || L == src || L.stat == DEAD || is_below_sound_pressure(T) || L.is_incorporeal())
			continue
		heard_something = TRUE
		var/feedback = list()
		feedback += "There are noises of movement "
		var/direction = get_dir(src, L)
		if(direction)
			feedback += "towards the [dir2text(direction)], "
			switch(get_dist(src, L) / client.view)
				if(0 to 0.2)
					feedback += "very close by."
				if(0.2 to 0.4)
					feedback += "close by."
				if(0.4 to 0.6)
					feedback += "some distance away."
				if(0.6 to 0.8)
					feedback += "further away."
				else
					feedback += "far away."
		else // No need to check distance if they're standing right on-top of us
			feedback += "right on top of you."
		to_chat(src,span_notice(jointext(feedback,null)))
	if(!heard_something)
		to_chat(src, span_notice("You hear no movement but your own."))

/mob/living/carbon/human/proc/regenerate()
	set name = "Regenerate"
	set desc = "Allows you to regrow limbs and heal organs after a period of rest."
	set category = VERB_CAT_ABILITIES_GENERAL

	if(nutrition < 250)
		to_chat(src, span_warning("You lack the biomass to begin regeneration!"))
		return

	if(active_regen)
		to_chat(src, span_warning("You are already regenerating tissue!"))
		return
	else
		active_regen = TRUE
		act_message(src, null, others = span_filter_notice(span_bold("%U%") + "'s flesh begins to mend..."))

	var/delay_length = round(active_regen_delay * species.active_regen_mult)
	task_timed(src, delay_length, target = src, receiver = src, on_done = PROC_REF(regenerate_human_done), done_args = list(), on_fail = PROC_REF(regenerate_human_failed), fail_args = list())

/mob/living/carbon/human/proc/regenerate_human_done()
	adjust_nutrition(-200)

	for(var/obj/item/organ/internal/I in internal_organ_list())
		if(I.is_robotic()) // No free robofix.
			continue
		if(I.damage > 0)
			mend(TREAT_RESTORATION, 30, I) //Repair functionally half of a dead internal organ.
			I.restore_status()	// Wipe status, as it's being regenerated from possibly dead (a dead brain stays dead).
			to_chat(src, span_notice("You feel a soothing sensation within your [I.name]..."))

	// Replace completely missing limbs.
	for(var/limb_type in src.species.has_limbs)
		var/obj/item/organ/external/E = src.organs_by_name[limb_type]

		if(E && E.disfigured)
			E.disfigured = 0
		if(E && (E.is_stump() || (E.status & (ORGAN_DESTROYED|ORGAN_DEAD|ORGAN_MUTATED))))
			E.removed()
			spent(E)
			E = null
		if(!E)
			var/list/organ_data = src.species.has_limbs[limb_type]
			var/limb_path = organ_data["path"]
			var/obj/item/organ/O = new limb_path(src)
			if(!is_registered(src.species))
				organ_data["descriptor"] = O.name
			to_chat(src, span_notice("You feel a slithering sensation as your [O.name] reform."))

			var/agony_to_apply = round(0.66 * O.max_damage) // 66% of the limb's health is converted into pain.
			injure(INJURY_PAIN, agony_to_apply, O.organ_tag)

	for(var/organtype in species.has_organ) // Replace completely missing internal organs. -After- external ones, so they all should exist.
		if(!src.organ_in(organtype))
			var/organpath = species.has_organ[organtype]
			var/obj/item/organ/Int = new organpath(src, TRUE)

			Int.rejuvenate(TRUE)

	body?.invalidate(BODY_DIRTY_ORGANS) // Update everything

	update_icons_body()
	active_regen = FALSE

/mob/living/carbon/human/proc/regenerate_human_failed()
	to_chat(src, span_critical("Your regeneration is interrupted!"))
	adjust_nutrition(-75)
	active_regen = FALSE

/mob/living/carbon/human/proc/setmonitor_state()
	set name = "Set monitor display"
	set desc = "Set your monitor display"
	set category = VERB_CAT_IC_SETTINGS
	if(stat)
		to_chat(src,span_warning("You must be awake and standing to perform this action!"))
		return
	var/obj/item/organ/external/head/E = organs_by_name[BP_HEAD]
	if(!E)
		to_chat(src,span_warning("You don't seem to have a head!"))
		return
	var/datum/robolimb/robohead = GLOB.all_robolimbs[E.model]
	if(!robohead.monitor_styles || !robohead.monitor_icon)
		to_chat(src,span_warning("Your head doesn't have a monitor, or it doesn't support being changed!"))
		return
	var/list/states
	if(!states)
		states = params2list(robohead.monitor_styles)
	open_request(src, /datum/prompt/choice/monitor_state, PROC_REF(monitor_state_chosen), answerer = src, choices = states, head = E)

/// Re-checked on the answer: conscious, and it's still our head.
/datum/prompt/choice/monitor_state
	title = "Screen Icon Choice"
	question = "Select a screen icon:"
	timeout = 0
	ask_flags = ASK_CONSCIOUS
	var/obj/item/organ/external/head/head
	var/head_expected = FALSE

CAPABILITIES(/datum/prompt/choice/monitor_state)
	ref_one(nameof(head), /obj/item/organ/external/head)

/datum/prompt/choice/monitor_state/prepare(datum/act/A)
	. = ..()
	var/obj/item/organ/external/head/captured_head = head
	head_expected = !isnull(captured_head)
	rel_clear(src, nameof(head))
	if(captured_head && !QDELETED(captured_head))
		rel_set(src, nameof(head), captured_head)

/datum/prompt/choice/monitor_state/recheck_extra()
	if(head_expected && QDELETED(head))
		return "gone"
	if(isnull(value))
		return
	var/mob/living/carbon/human/H = answerer
	return H.organs_by_name[BP_HEAD] == head ? null : "head changed"

/mob/living/carbon/human/proc/monitor_state_chosen(datum/act/request/A)
	if(!A.answer)
		return
	return monitor_state_apply(A)

/mob/living/carbon/human/proc/monitor_state_apply(datum/act/request/A)
	var/datum/prompt/choice/monitor_state/ask = A.answer
	var/obj/item/organ/external/head/E = ask.head
	var/list/states = ask.choices
	var/choice = ask.value
	var/datum/robolimb/robohead = GLOB.all_robolimbs[E.model]
	if(robohead?.monitor_icon)
		E.eye_icon_location = robohead.monitor_icon
		E.eye_icon = states[choice]
		E.eye_icon_override = TRUE
		to_chat(src,span_warning("You set your monitor to display [choice]!"))
		update_icons_body()


/mob/living/carbon/human/proc/reagent_purge()
	set name = "Purge Reagents"
	set desc = "Empty yourself of any reagents you may have consumed or come into contact with."
	set category = VERB_CAT_IC_GAME

	if(stat == DEAD) return

	to_chat(src, span_notice("Performing reagent purge, please wait..."))
	after(src, 5 SECONDS, PROC_REF(reagent_purge_done))
	return TRUE

/mob/living/carbon/human/proc/reagent_purge_done()
	src.bloodstr.clear_reagents()
	src.ingested.clear_reagents()
	src.touching.clear_reagents()
	to_chat(src, span_notice("Reagents purged!"))

/mob/living/carbon/human/verb/toggle_eyes_layer()
	set name = "Switch Eyes/Monitor Layer"
	set desc = "Toggle rendering of eyes/monitor above markings."
	set category = VERB_CAT_IC_SETTINGS

	if(stat)
		to_chat(src, span_warning("You must be awake and standing to perform this action!"))
		return
	var/obj/item/organ/external/head/H = organs_by_name[BP_HEAD]
	if(!H)
		to_chat(src, span_warning("You don't seem to have a head!"))
		return

	H.eyes_over_markings = !H.eyes_over_markings
	update_icons_body()

	if(H.robotic)
		var/datum/robolimb/robohead = GLOB.all_robolimbs[H.model]
		if(robohead.monitor_styles && robohead.monitor_icon)
			to_chat(src, span_notice("You reconfigure the rendering order of your facial display."))

	return TRUE

//////////// Hand games that can be played by people next to each other, or over a small table.

/mob/living/carbon/human/verb/hand_games()
	set name = "Play Hand Games"
	set desc = "Choose from a variety of hand games to play with someone next to you or across a small table."
	set category = VERB_CAT_IC_GAME

	if(stat)
		return

	var/obj/item/organ/external/l_hand = get_organ(BP_L_HAND)
	var/obj/item/organ/external/r_hand = get_organ(BP_R_HAND)
	if((!l_hand || l_hand.is_stump()) && (!r_hand || r_hand.is_stump()))
		to_chat(src, span_warning("You have no hands to play games with!"))
		return

	var/list/nearby = list()
	for(var/mob/living/carbon/human/H in range(src,1))
		if(H.stat)
			continue
		if(H == src)
			continue
		var/obj/item/organ/external/l_hand2 = H.get_organ(BP_L_HAND)
		var/obj/item/organ/external/r_hand2 = H.get_organ(BP_R_HAND)
		if((!l_hand2 || l_hand2.is_stump()) && (!r_hand2 || r_hand2.is_stump()))
			continue
		nearby |= H
	for(var/obj/structure/table/T in range(src, 1))
		for(var/mob/living/carbon/human/H in range(T,1))
			if(H.stat)
				continue
			if(H == src)
				continue
			var/obj/item/organ/external/l_hand2 = H.get_organ(BP_L_HAND)
			var/obj/item/organ/external/r_hand2 = H.get_organ(BP_R_HAND)
			if((!l_hand2 || l_hand2.is_stump()) && (!r_hand2 || r_hand2.is_stump()))
				continue
			nearby |= H

	if(!nearby.len)
		to_chat(src, span_warning("There is nobody nearby to play games with!"))

	open_request(src, /datum/prompt/choice, PROC_REF(hand_games_partner_chosen), answerer = src, title = "Hand games", question = "Choose a game partner:", choices = nearby, ask_flags = ASK_CONSCIOUS, timeout = 0)

/// Which game to play; carries the partner without retaining either participant.
/datum/prompt/choice/hand_game
	title = "Hand games"
	choices = list("Rock, Paper, Scissors", "Arm Wrestling", "Slap Hands", "Thumb Wars", "Cancel")
	buttons = TRUE
	ask_flags = ASK_CONSCIOUS
	timeout = 0
	var/mob/living/carbon/human/partner

CAPABILITIES(/datum/prompt/choice/hand_game)
	ref_one(nameof(partner), /mob/living/carbon/human)

/datum/prompt/choice/hand_game/prepare(datum/act/A)
	..()
	var/mob/living/carbon/human/captured_partner = partner
	rel_clear(src, nameof(partner))
	rel_set(src, nameof(partner), captured_partner)
	question = "Choose a game to play with [partner]?"

/datum/prompt/choice/hand_game/recheck_extra()
	return QDELETED(partner) ? "gone" : null

/mob/living/carbon/human/proc/hand_games_partner_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/living/carbon/human/partner = A.answer.value
	if(!istype(partner) || QDELETED(partner))
		return
	open_request(src, /datum/prompt/choice/hand_game, PROC_REF(hand_games_chosen), answerer = src, partner = partner)

/mob/living/carbon/human/proc/hand_games_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/hand_game/ask = A.answer
	if(ask.value == "Cancel" || QDELETED(ask.partner))
		return
	hand_game_invite(ask.partner, ask.value)

// Checks to make sure everything is fine to continue playing.
/mob/living/carbon/human/proc/hand_games_check(mob/living/carbon/human/player1, mob/living/carbon/human/player2)
	if(!istype(player1) || !istype(player2))
		return 0
	if(player1.stat || player2.stat) //Make sure they're still standing
		return 0
	if(!(player2 in range(player1,2))) //Just make sure they're within 2 spaces still.
		return 0
	return 1

/// Each answered step rechecks the original pair; cancellation is a decline even after movement.
/mob/living/carbon/human/proc/hand_game_invite(mob/living/carbon/human/player2, game)
	open_request(src, /datum/prompt/choice/hand_game_invite, PROC_REF(hand_game_invitation_answered), answerer = player2, asker = src, partner = player2, game = game)

/datum/prompt/choice/hand_game_move
	buttons = TRUE
	timeout = 0
	var/mob/living/carbon/human/partner
	var/game
	var/choice1
	var/second_move = FALSE

CAPABILITIES(/datum/prompt/choice/hand_game_move)
	ref_one(nameof(partner), /mob/living/carbon/human)

/datum/prompt/choice/hand_game_move/prepare(datum/act/A)
	..()
	var/mob/living/carbon/human/captured_partner = partner
	rel_clear(src, nameof(partner))
	rel_set(src, nameof(partner), captured_partner)

/datum/prompt/choice/hand_game_move/recheck_extra()
	var/mob/living/carbon/human/player1 = owner
	if(QDELETED(player1) || QDELETED(partner))
		return "gone"
	return player1.hand_games_check(player1, partner) ? null : "can't play"

/datum/prompt/choice/hand_game_invite
	parent_type = /datum/prompt/choice/hand_game_move
	choices = list("Play", "Refuse")
	var/initial_refusal

/datum/prompt/choice/hand_game_invite/begin()
	initial_refusal = request_recheck(src)
	if(initial_refusal)
		request_end(src, REQ_CANCELLED, null)
		return
	var/mob/living/carbon/human/player1 = owner
	to_chat(player1, span_notice("Asking [partner] if they want to play [game]!"))
	return ..()

/datum/prompt/choice/hand_game_invite/prepare(datum/act/A)
	..()
	title = game
	question = "[asker] wants to play [game]."

/datum/prompt/choice/hand_game_invite/recheck_extra()
	// A refused legacy confirm stops before the flow's continuation recheck.
	if(value == "Refuse")
		return null
	return ..()

/datum/prompt/number/hand_game_move
	min_value = 1
	max_value = 10
	step = 1
	default = 5
	timeout = 0
	var/mob/living/carbon/human/partner
	var/game
	var/choice1
	var/second_move = FALSE

CAPABILITIES(/datum/prompt/number/hand_game_move)
	ref_one(nameof(partner), /mob/living/carbon/human)

/datum/prompt/number/hand_game_move/prepare(datum/act/A)
	..()
	var/mob/living/carbon/human/captured_partner = partner
	rel_clear(src, nameof(partner))
	rel_set(src, nameof(partner), captured_partner)

/datum/prompt/number/hand_game_move/recheck_extra()
	var/mob/living/carbon/human/player1 = owner
	if(QDELETED(player1) || QDELETED(partner))
		return "gone"
	return player1.hand_games_check(player1, partner) ? null : "can't play"

/mob/living/carbon/human/proc/hand_game_invitation_answered(datum/act/request/A)
	var/datum/prompt/choice/hand_game_invite/ask = A.request
	if(ask.initial_refusal || QDELETED(ask.partner) || QDELETED(ask.answerer))
		return
	if(ask.value == "Refuse" || (ask.outcome == REQ_CANCELLED && isnull(ask.value)))
		to_chat(src, span_warning("[ask.partner] declines to play the game."))
		return
	if(!A.answer)
		return
	hand_game_invite_answered(ask.partner, ask.game)
	if(ask.game != "Thumb Wars")
		ask_hand_game_move(ask.partner, ask.game, null, FALSE)

/// Move questions remain integer-valued or literal choices, including the playable "Cancel" choice.
/mob/living/carbon/human/proc/ask_hand_game_move(mob/living/carbon/human/player2, game, choice1, second_move)
	var/mob/living/carbon/human/player = second_move ? player2 : src
	switch(game)
		if("Rock, Paper, Scissors")
			open_request(src, /datum/prompt/choice/hand_game_move, PROC_REF(hand_game_move_answered), answerer = player, asker = src, partner = player2, game = game, choice1 = choice1, second_move = second_move, question = "Choose your attack!", title = "Rock, Paper, Scissors", choices = list("Rock", "Paper", "Scissors", "Cancel"))
		if("Arm Wrestling")
			open_request(src, /datum/prompt/number/hand_game_move, PROC_REF(hand_game_move_answered), answerer = player, asker = src, partner = player2, game = game, choice1 = choice1, second_move = second_move, question = "How strong is your character on a scale of 1 to 10 (1 being a weakling, 10 being very strong).", title = "Strength")
		if("Slap Hands")
			open_request(src, /datum/prompt/number/hand_game_move, PROC_REF(hand_game_move_answered), answerer = player, asker = src, partner = player2, game = game, choice1 = choice1, second_move = second_move, question = "How fast are your character's reaction times on a scale of 1 to 10 (1 being slow, 10 being very fast).", title = "Speed")

/mob/living/carbon/human/proc/hand_game_move_answered(datum/act/request/A)
	var/datum/request/request = A.request
	var/mob/living/carbon/human/player2
	var/game
	var/choice1
	var/second_move
	if(istype(request, /datum/prompt/choice/hand_game_move))
		var/datum/prompt/choice/hand_game_move/pick = request
		player2 = pick.partner
		game = pick.game
		choice1 = pick.choice1
		second_move = pick.second_move
	else
		var/datum/prompt/number/hand_game_move/amount = request
		player2 = amount.partner
		game = amount.game
		choice1 = amount.choice1
		second_move = amount.second_move
	if(QDELETED(player2) || QDELETED(request.answerer))
		return
	if(!A.answer)
		if(request.outcome == REQ_CANCELLED && isnull(request.value))
			to_chat(src, span_warning("[player2] declines to play the game."))
		return
	if(second_move)
		hand_game_second_choice(player2, game, choice1, request.value)
		return
	choice1 = request.value
	if(choice1 == "Cancel")
		act_message(src, null, others = span_notice("%U% chickens out!"))
	to_chat(src, span_warning("[player2] is [game == "Rock, Paper, Scissors" ? "deciding" : "getting ready"]."))
	ask_hand_game_move(player2, game, choice1, TRUE)

/mob/living/carbon/human/proc/hand_game_invite_answered(mob/living/carbon/human/player2, game)
	switch(game)
		if("Rock, Paper, Scissors")
			act_message(src, player2, others = span_notice("%U% challenges %T% to Rock, Paper, Scissors!"))
			to_chat(player2, span_warning("[src] is deciding."))
		if("Arm Wrestling")
			act_message(src, player2, others = span_notice("%U% challenges %T% to Arm Wrestling!"))
			to_chat(player2, span_warning("[src] is getting ready."))
		if("Slap Hands")
			act_message(src, player2, others = span_notice("%U% challenges %T% to Slap Hands!"))
			to_chat(player2, span_warning("[src] is getting ready."))
		if("Thumb Wars")
			act_message(src, player2, others = span_notice("%U% challenges %T% to a thumb war!"))
			task_start(/datum/task/timed/human_game_thumbwars_human, src, player2, receiver = src)

/mob/living/carbon/human/proc/hand_game_second_choice(mob/living/carbon/human/player2, game, choice1, choice2)
	if(choice2 == "Cancel")
		act_message(player2, null, others = span_notice("%U% chickens out!"))
	switch(game)
		if("Rock, Paper, Scissors")
			if(choice1 == choice2)
				act_message(src, player2, others = span_notice("%U% and %T% both choose [choice1], it's a draw!"))
			else
				act_message(src, null, others = span_notice("%U% chooses [choice1]!"))
				act_message(player2, null, others = span_notice("%U% chooses [choice2]!"))
		if("Arm Wrestling")
			// Each player's strength counts for their size.
			var/score1 = size_multiplier * clamp(choice1, 1, 10)
			var/score2 = player2.size_multiplier * clamp(choice2, 1, 10)
			var/competition = pick(score1;src, score2;player2)
			task_start(/datum/task/timed/human_game_armwrestle_human, src, player2, receiver = src, competition = competition)
		if("Slap Hands")
			// This one gives the advantage to smaller players.
			var/score1 = clamp(2.25 - size_multiplier, 0.1, 3) * clamp(choice1, 1, 10)
			var/score2 = clamp(2.25 - player2.size_multiplier, 0.1, 3) * clamp(choice2, 1, 10)
			var/competition = pick(score1;src, score2;player2)
			task_start(/datum/task/timed/human_game_slaphands_human, src, player2, receiver = src, competition = competition)

/////// Arm wrestling! Each player gets a modifier based on their size and can choose the strength of their character, then a weighted roll is made.

/datum/task/timed/human_game_armwrestle_human
	duration = 5 SECONDS
	complete_proc = /mob/living/carbon/human/proc/game_armwrestle_human_done
	cancel_proc = /mob/living/carbon/human/proc/game_armwrestle_human_failed
	var/competition

/mob/living/carbon/human/proc/game_armwrestle_human_done(datum/task/timed/human_game_armwrestle_human/task)
	var/mob/living/carbon/human/player1 = task.actor
	var/mob/living/carbon/human/player2 = task.target
	var/competition = task.competition
	if(!hand_games_check(player1,player2))
		return
	if(competition == player1)
		act_message(player1, player2, others = span_notice("%U% manages to overpower %T% and pin their arm down!"))
	else
		act_message(player2, player1, others = span_notice("%U% manages to overpower %T% and pin their arm down!"))

/mob/living/carbon/human/proc/game_armwrestle_human_failed(datum/task/timed/human_game_armwrestle_human/task)
	var/mob/living/carbon/human/player2 = task.target
	player2.visible_message(span_notice("The players cancelled their competition!"))
	return 0

/////// Slap Hands! Each player gets a modifier based on their size and can choose the reaction time of their character, then a weighted roll is made. This one gives the advantage to smaller players.

/datum/task/timed/human_game_slaphands_human
	duration = 1 SECOND
	complete_proc = /mob/living/carbon/human/proc/game_slaphands_human_done
	cancel_proc = /mob/living/carbon/human/proc/game_slaphands_human_failed
	var/competition

/mob/living/carbon/human/proc/game_slaphands_human_done(datum/task/timed/human_game_slaphands_human/task)
	var/mob/living/carbon/human/player1 = task.actor
	var/mob/living/carbon/human/player2 = task.target
	var/competition = task.competition
	if(!hand_games_check(player1,player2))
		return
	play_sfx(player1, SFX_EFFECTS_SNAP, 0.6)
	if(competition == player1)
		act_message(player1, player2, others = span_notice("%U% manages to slap %T%'s hand before they can react!"))
	else
		act_message(player2, player1, others = span_notice("%U% manages to slap %T%'s hand before they can react!"))

/mob/living/carbon/human/proc/game_slaphands_human_failed(datum/task/timed/human_game_slaphands_human/task)
	var/mob/living/carbon/human/player2 = task.target
	player2.visible_message(span_notice("The players cancelled their competition!"))
	return 0

///// Thumb wars! This one is just pure chance to allow people to do just quick RNG.

/datum/task/timed/human_game_thumbwars_human
	duration = 5 SECONDS
	complete_proc = /mob/living/carbon/human/proc/game_thumbwars_human_done
	cancel_proc = /mob/living/carbon/human/proc/game_thumbwars_human_failed

/mob/living/carbon/human/proc/game_thumbwars_human_done(datum/task/timed/human_game_thumbwars_human/task)
	var/mob/living/carbon/human/player1 = task.actor
	var/mob/living/carbon/human/player2 = task.target
	if(!hand_games_check(player1,player2))
		return
	if(prob(50))
		act_message(player1, player2, others = span_notice("After a gruelling battle, %U% eventually manages to subdue the thumb of %T%!"))
	else
		act_message(player2, player1, others = span_notice("After a gruelling battle, %U% eventually manages to subdue the thumb of %T%!"))

/mob/living/carbon/human/proc/game_thumbwars_human_failed(datum/task/timed/human_game_thumbwars_human/task)
	var/mob/living/carbon/human/player2 = task.target
	player2.visible_message(span_notice("The players cancelled their thumb war!"))
	return 0

///Play dead for sparkledog memes

/mob/living/carbon/human/proc/play_dead()
	set name = "Play Dead"
	set desc = "Literally just die on the spot. It's okay, you can get better."
	set category = VERB_CAT_ABILITIES_SPARKLEDOG

	if(stat)
		to_chat(src, span_warning("You're too messed up right now to act all messed up, it's, like, for real."))
		return

	if(!resting)
		SetResting(1)
		apply_body_effect(/datum/body_effect/play_dead, null, src) //Tracks whether they are still resting to remove the status indicator
		add_status_indicator("dead")
		act_message(src, null, others = span_warning("%U% literally just dies!"))
	else
		SetResting(0)

/datum/body_effect/play_dead
	stacks = MODIFIER_STACK_FORBID
	tick_interval = 2 SECONDS
	name = "playing dead"
	desc = "You are are pretending to be dead, you aren't very convincing!"
	on_created_text = span_notice("You begin to play dead!")
	on_expired_text = span_notice("You got better.")

/datum/body_effect/play_dead/on_tick(mob/living/L)
	if(!L.resting)
		L.end_body_effect(type)

/datum/body_effect/play_dead/on_end(mob/living/L, expired)
	L.remove_status_indicator("dead")
	act_message(L, null, others = span_warning("%U% literally just dies!"))
