// These should all be procs, you can add them to humans/subspecies by
// species.dm's inherent_verbs ~ Z

/mob/living/carbon/human/proc/tie_hair()
	set name = "Tie Hair"
	set desc = "Style your hair."
	set category = "IC.Game"

	if(incapacitated())
		to_chat(src, span_warning("You can't mess with your hair right now!"))
		return

	if(h_style)
		var/datum/sprite_accessory/hair/hair_style = GLOB.hair_styles_list[h_style]
		var/selected_string
		if(!(hair_style.flags & HAIR_TIEABLE))
			to_chat(src, span_warning("Your hair isn't long enough to tie."))
			return
		else
			var/list/datum/sprite_accessory/hair/valid_hairstyles = list()
			for(var/hair_string in GLOB.hair_styles_list)
				var/datum/sprite_accessory/hair/test = GLOB.hair_styles_list[hair_string]
				if(test.flags & HAIR_TIEABLE)
					valid_hairstyles.Add(hair_string)
			selected_string = tgui_input_list(src, "Select a new hairstyle", "Your hairstyle", valid_hairstyles)
		if(incapacitated())
			to_chat(src, span_warning("You can't mess with your hair right now!"))
			return
		else if(selected_string && h_style != selected_string)
			h_style = selected_string
			regenerate_icons()
			visible_message(span_notice("[src] pauses a moment to style their hair."))
		else
			to_chat(src, span_notice("You're already using that style."))

/mob/living/carbon/human/proc/tackle()
	set category = "Abilities.General"
	set name = "Tackle"
	set desc = "Tackle someone down."

	if(last_special > world.time)
		return

	if(stat || paralysis || stunned || weakened || lying || restrained() || buckled)
		to_chat(src, span_notice("You cannot tackle someone in your current state."))
		return

	var/list/choices = list()
	for(var/mob/living/M in view(1,src))
		if(!istype(M,/mob/living/silicon) && Adjacent(M))
			choices += M
	choices -= src

	var/mob/living/T = tgui_input_list(src, "Who do you wish to tackle?", "Target Choice", choices)

	if(!T || !src || src.stat) return

	if(!Adjacent(T)) return

	if(last_special > world.time)
		return

	if(stat || paralysis || stunned || weakened || lying || restrained() || buckled)
		to_chat(src, span_notice("You cannot tackle in your current state."))
		return

	last_special = world.time + 50

	var/failed
	if(prob(75))
		T.Weaken(rand(0.5,3))
	else
		failed = 1

	playsound(src, 'sound/weapons/pierce.ogg', 25, 1, -1)
	if(failed)
		src.Weaken(rand(2,4))

	for(var/mob/O in viewers(src, null))
		if ((O.client && !( O.blinded )))
			O.show_message(span_warning(span_red(span_bold("[src] [failed ? "tried to tackle" : "has tackled"] down [T]!"))), 1)

/mob/living/carbon/human/proc/commune()
	set category = "Abilities.General"
	set name = "Commune with creature"
	set desc = "Send a telepathic message to an unlucky recipient."

	var/list/targets = list()
	var/target = null
	var/text = null

	targets += getmobs() //Fill list, prompt user with list
	target = tgui_input_list(src, "Select a creature!", "Speak to creature", targets)

	if(!target) return

	text = tgui_input_text(src, "What would you like to say?", "Speak to creature", null, MAX_MESSAGE_LEN)

	if(!text) return

	var/mob/M = targets[target]

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
	set category = "Abilities.General"

	var/msg = tgui_input_text(src, "Message:", "Psychic Whisper", "", MAX_MESSAGE_LEN)
	if(msg)
		log_talk("(PWHISPER to [key_name(M)]) [msg]", LOG_WHISPER)
		to_chat(M, span_filter_say("[span_green("You hear a strange, alien voice in your head... <i>[msg]</i>")]"))
		to_chat(src, span_filter_say("[span_green("You said: \"[msg]\" to [M]")]"))
	return

/mob/living/carbon/human/proc/diona_split_nymph()
	set name = "Split"
	set desc = "Split your humanoid form into its constituent nymphs."
	set category = "Abilities.Diona"
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

	for(var/mob/living/carbon/alien/diona/D in src)
		nymphs++
		D.forceMove(T)
		transfer_languages(src, D, WHITELISTED|RESTRICTED)
		D.set_dir(pick(NORTH, SOUTH, EAST, WEST))

	if(nymphs < number_of_resulting_nymphs)
		for(var/i in nymphs to (number_of_resulting_nymphs - 1))
			var/mob/M = new /mob/living/carbon/alien/diona(T)
			transfer_languages(src, M, WHITELISTED|RESTRICTED)
			M.set_dir(pick(NORTH, SOUTH, EAST, WEST))


	for(var/obj/item/W in src)
		drop_from_inventory(W)

	var/obj/item/organ/external/Chest = organs_by_name[BP_TORSO]

	if(Chest.robotic >= 2)
		visible_message(span_warning("\The [src] shudders slightly, then ejects a cluster of nymphs with a wet slithering noise."))
		species = GLOB.all_species[SPECIES_HUMAN] // This is hard-set to default the body to a normal FBP, without changing anything.

		// Bust it
		src.death()

		for(var/obj/item/organ/internal/diona/Org in internal_organs) // Remove Nymph organs.
			qdel(Org)

		// Purge the diona verbs.
		remove_verb(src, /mob/living/carbon/human/proc/diona_split_nymph)
		remove_verb(src, /mob/living/carbon/human/proc/regenerate)

		for(var/obj/item/organ/external/E in organs) // Just fall apart.
			E.droplimb(TRUE)

	else
		visible_message(span_warning("\The [src] quivers slightly, then splits apart with a wet slithering noise."))
		qdel(src)

/mob/living/carbon/human/proc/self_diagnostics()
	set name = "Self-Diagnostics"
	set desc = "Run an internal self-diagnostic to check for damage."
	set category = "Abilities.General"

	if(stat == DEAD) return

	to_chat(src, span_notice("Performing self-diagnostic, please wait..."))

	spawn(50)
		var/output = span_filter_notice("Self-Diagnostic Results:\n")

		output += "Internal Temperature: [convert_k2c(bodytemperature)] Degrees Celsius\n"

		if(isSynthetic())
			output += "Current Battery Charge: [nutrition]\n"

			var/toxDam = getToxLoss()
			if(toxDam)
				output += "System Instability: " + span_warning("[toxDam > 25 ? "Severe" : "Moderate"]") + ". Seek charging station for cleanup.\n"
			else
				output += "System Instability: " + span_green("OK") + "\n"

		for(var/obj/item/organ/external/EO in organs)
			if(EO.robotic >= ORGAN_ASSISTED)
				if(EO.brute_dam || EO.burn_dam)
					output += "[EO.name] - " + span_warning("[EO.burn_dam + EO.brute_dam > EO.min_broken_damage ? "Heavy Damage" : "Light Damage"]") + "\n" //VOREStation Edit - Makes robotic limb damage scalable
				else
					output += "[EO.name] - " + span_green("OK") + "\n"

		for(var/obj/item/organ/IO in internal_organs)
			if(IO.robotic >= ORGAN_ASSISTED)
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
	set category = "Abilities.General"

	if(incapacitated())
		to_chat(src, span_warning("You need to recover before you can use this ability."))
		return
	if(world.time < next_sonar_ping)
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
	set category = "Abilities.General"

	if(nutrition < 250)
		to_chat(src, span_warning("You lack the biomass to begin regeneration!"))
		return

	if(active_regen)
		to_chat(src, span_warning("You are already regenerating tissue!"))
		return
	else
		active_regen = TRUE
		src.visible_message(span_filter_notice(span_bold("[src]") + "'s flesh begins to mend..."))

	var/delay_length = round(active_regen_delay * species.active_regen_mult)
	if(do_after(src, delay_length, target = src))
		adjust_nutrition(-200)

		for(var/obj/item/organ/I in internal_organs)
			if(I.robotic >= ORGAN_ROBOT) // No free robofix.
				continue
			if(I.damage > 0)
				I.damage = max(I.damage - 30, 0) //Repair functionally half of a dead internal organ.
				I.status = 0	// Wipe status, as it's being regenerated from possibly dead.
				to_chat(src, span_notice("You feel a soothing sensation within your [I.name]..."))

		// Replace completely missing limbs.
		for(var/limb_type in src.species.has_limbs)
			var/obj/item/organ/external/E = src.organs_by_name[limb_type]

			if(E && E.disfigured)
				E.disfigured = 0
			if(E && (E.is_stump() || (E.status & (ORGAN_DESTROYED|ORGAN_DEAD|ORGAN_MUTATED))))
				E.removed()
				qdel(E)
				E = null
			if(!E)
				var/list/organ_data = src.species.has_limbs[limb_type]
				var/limb_path = organ_data["path"]
				var/obj/item/organ/O = new limb_path(src)
				organ_data["descriptor"] = O.name
				to_chat(src, span_notice("You feel a slithering sensation as your [O.name] reform."))

				var/agony_to_apply = round(0.66 * O.max_damage) // 66% of the limb's health is converted into pain.
				src.apply_damage(agony_to_apply, HALLOSS)

		for(var/organtype in species.has_organ) // Replace completely missing internal organs. -After- external ones, so they all should exist.
			if(!src.internal_organs_by_name[organtype])
				var/organpath = species.has_organ[organtype]
				var/obj/item/organ/Int = new organpath(src, TRUE)

				Int.rejuvenate(TRUE)

		handle_organs() // Update everything

		update_icons_body()
		active_regen = FALSE
	else
		to_chat(src, span_critical("Your regeneration is interrupted!"))
		adjust_nutrition(-75)
		active_regen = FALSE

/mob/living/carbon/human/proc/setmonitor_state()
	set name = "Set monitor display"
	set desc = "Set your monitor display"
	set category = "IC.Settings"
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
	var/choice = tgui_input_list(src, "Select a screen icon:", "Screen Icon Choice", states)
	if(choice)
		E.eye_icon_location = robohead.monitor_icon
		E.eye_icon = states[choice]
		E.eye_icon_override = TRUE
		to_chat(src,span_warning("You set your monitor to display [choice]!"))
		update_icons_body()


// === merged from human_powers_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/mob/living/carbon/human/proc/reagent_purge()
	set name = "Purge Reagents"
	set desc = "Empty yourself of any reagents you may have consumed or come into contact with."
	set category = "IC.Game"

	if(stat == DEAD) return

	to_chat(src, span_notice("Performing reagent purge, please wait..."))
	sleep(50)
	src.bloodstr.clear_reagents()
	src.ingested.clear_reagents()
	src.touching.clear_reagents()
	to_chat(src, span_notice("Reagents purged!"))

	return TRUE

/mob/living/carbon/human/verb/toggle_eyes_layer()
	set name = "Switch Eyes/Monitor Layer"
	set desc = "Toggle rendering of eyes/monitor above markings."
	set category = "IC.Settings"

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
	set category = "IC.Game"

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

	var/partner = tgui_input_list(src, "Choose a game partner:", "Hand games", nearby)
	if(!partner)
		return
	var/choose_game = tgui_alert(src, "Choose a game to play with [partner]?", "Hand games", list("Rock, Paper, Scissors", "Arm Wrestling", "Slap Hands", "Thumb Wars", "Cancel"))

	if(!choose_game || (choose_game == "Cancel"))
		return

	if(choose_game == "Rock, Paper, Scissors")
		game_rps(src,partner)

	if(choose_game == "Arm Wrestling")
		game_armwrestle(src,partner)

	if(choose_game == "Slap Hands")
		game_slaphands(src,partner)

	if(choose_game == "Thumb Wars")
		game_thumbwars(src,partner)

// Checks to make sure everything is fine to continue playing.

/mob/living/carbon/human/proc/hand_games_check(mob/living/carbon/human/player1, mob/living/carbon/human/player2)
	if(!istype(player1) || !istype(player2))
		return 0
	if(player1.stat || player2.stat) //Make sure they're still standing
		return 0
	if(!(player2 in range(player1,2))) //Just make sure they're within 2 spaces still.
		return 0

	return 1

///// A simple game of rock paper scissors, each player chooses an option and the choices are declared simultaneously.

/mob/living/carbon/human/proc/game_rps(mob/living/carbon/human/player1, mob/living/carbon/human/player2)
	if(!hand_games_check(player1,player2))
		return
	to_chat(player1, span_notice("Asking [player2] if they want to play Rock, Paper, Scissors!"))
	var/playgame = tgui_alert(player2, "[player1] wants to play Rock, Paper, Scissors.", "Rock, Paper, Scissors", list("Play", "Refuse"))
	if(!playgame || (playgame == "Refuse"))
		to_chat(player1, span_warning("[player2] declines to play the game."))
		return
	else
		player1.visible_message(span_notice("[player1] challenges [player2] to Rock, Paper, Scissors!"))
		to_chat(player2, span_warning("[player1] is deciding."))
		var/choice1 = tgui_alert(player1, "Choose your attack!", "Rock, Paper, Scissors", list("Rock", "Paper", "Scissors", "Cancel"))
		if(choice1 == "Cancel")
			player1.visible_message(span_notice("[player1] chickens out!"))
		if(!hand_games_check(player1,player2))
			return
		to_chat(player1, span_warning("[player2] is deciding."))
		var/choice2 = tgui_alert(player2, "Choose your attack!", "Rock, Paper, Scissors", list("Rock", "Paper", "Scissors", "Cancel"))
		if(choice2 == "Cancel")
			player2.visible_message(span_notice("[player2] chickens out!"))
		if(!hand_games_check(player1,player2))
			return
		if(choice1 == choice2)
			player1.visible_message(span_notice("[player1] and [player2] both choose [choice1], it's a draw!"))
		else
			player1.visible_message(span_notice("[player1] chooses [choice1]!"))
			player2.visible_message(span_notice("[player2] chooses [choice2]!"))

/////// Arm wrestling! Each player gets a modifier based on their size and can choose the strength of their character, then a weighted roll is made.

/mob/living/carbon/human/proc/game_armwrestle(mob/living/carbon/human/player1, mob/living/carbon/human/player2)
	if(!hand_games_check(player1,player2))
		return
	to_chat(player1, span_notice("Asking [player2] if they want to play Arm Wrestling!"))
	var/playgame = tgui_alert(player2, "[player1] wants to play Arm Wrestling.", "Arm Wrestling", list("Play", "Refuse"))
	if(!playgame || (playgame == "Refuse"))
		to_chat(player1, span_warning("[player2] declines to play the game."))
		return
	else
		if(!hand_games_check(player1,player2))
			return
		player1.visible_message(span_notice("[player1] challenges [player2] to Arm Wrestling!"))
		var/scale1 = player1.size_multiplier
		var/scale2 = player2.size_multiplier
		to_chat(player2, span_warning("[player1] is getting ready."))
		var/strength1 = tgui_input_number(player1, "How strong is your character on a scale of 1 to 10 (1 being a weakling, 10 being very strong).", "Strength")
		strength1 = clamp(strength1, 1, 10)
		if(!strength1)
			player1.visible_message(span_notice("[player1] chickens out!"))
		if(!hand_games_check(player1,player2))
			return
		to_chat(player1, span_warning("[player2] is getting ready."))
		var/strength2 = tgui_input_number(player2, "How strong is your character on a scale of 1 to 10 (1 being a weakling, 10 being very strong).", "Strength")
		strength2 = clamp(strength2, 1, 10)
		if(!strength2)
			player2.visible_message(span_notice("[player2] chickens out!"))
		if(!hand_games_check(player1,player2))
			return

		var/score1 = (scale1 * strength1)
		var/score2 = (scale2 * strength2)

		var/competition = pick(score1;player1, score2;player2)
		if(!do_after(player1, 5 SECONDS, target = player2))
			player2.visible_message(span_notice("The players cancelled their competition!"))
			return 0
		if(!hand_games_check(player1,player2))
			return
		if(competition == player1)
			player1.visible_message(span_notice("[player1] manages to overpower [player2] and pin their arm down!"))
		else
			player2.visible_message(span_notice("[player2] manages to overpower [player1] and pin their arm down!"))

/////// Slap Hands! Each player gets a modifier based on their size and can choose the reaction time of their character, then a weighted roll is made. This one gives the advantage to smaller players.

/mob/living/carbon/human/proc/game_slaphands(mob/living/carbon/human/player1, mob/living/carbon/human/player2)
	if(!hand_games_check(player1,player2))
		return
	to_chat(player1, span_notice("Asking [player2] if they want to play Slap Hands!"))
	var/playgame = tgui_alert(player2, "[player1] wants to play Slap Hands.", "Slap Hands", list("Play", "Refuse"))
	if(!playgame || (playgame == "Refuse"))
		to_chat(player1, span_warning("[player2] declines to play the game."))
		return
	else
		if(!hand_games_check(player1,player2))
			return
		player1.visible_message(span_notice("[player1] challenges [player2] to Slap Hands!"))
		var/scale1 = (2.25 - player1.size_multiplier)
		scale1 = clamp(scale1, 0.1, 3)
		var/scale2 = (2.25 - player2.size_multiplier)
		scale2 = clamp(scale2, 0.1, 3)
		to_chat(player2, span_warning("[player1] is getting ready."))
		var/strength1 = tgui_input_number(player1, "How fast are your character's reaction times on a scale of 1 to 10 (1 being slow, 10 being very fast).", "Speed")
		strength1 = clamp(strength1, 1, 10)
		if(!strength1)
			player1.visible_message(span_notice("[player1] chickens out!"))
		if(!hand_games_check(player1,player2))
			return
		to_chat(player1, span_warning("[player2] is getting ready."))
		var/strength2 = tgui_input_number(player2, "How fast are your character's reaction times on a scale of 1 to 10 (1 being slow, 10 being very fast).", "Speed")
		strength2 = clamp(strength2, 1, 10)
		if(!strength2)
			player2.visible_message(span_notice("[player2] chickens out!"))
		if(!hand_games_check(player1,player2))
			return

		var/score1 = (scale1 * strength1)
		var/score2 = (scale2 * strength2)

		var/competition = pick(score1;player1, score2;player2)
		if(!do_after(player1, 1 SECOND, target = player2))
			player2.visible_message(span_notice("The players cancelled their competition!"))
			return 0
		if(!hand_games_check(player1,player2))
			return
		playsound(player1, 'sound/effects/snap.ogg', 30, 1)
		if(competition == player1)
			player1.visible_message(span_notice("[player1] manages to slap [player2]'s hand before they can react!"))
		else
			player2.visible_message(span_notice("[player2] manages to slap [player1]'s hand before they can react!"))

///// Thumb wars! This one is just pure chance to allow people to do just quick RNG.

/mob/living/carbon/human/proc/game_thumbwars(mob/living/carbon/human/player1, mob/living/carbon/human/player2)
	if(!hand_games_check(player1,player2))
		return
	to_chat(player1, span_notice("Asking [player2] if they want to play Thumb Wars!"))
	var/playgame = tgui_alert(player2, "[player1] wants to play Thumb Wars.", "Thumb Wars", list("Play", "Refuse"))
	if(!playgame || (playgame == "Refuse"))
		to_chat(player1, span_warning("[player2] declines to play the game."))
		return
	else
		if(!hand_games_check(player1,player2))
			return
		player1.visible_message(span_notice("[player1] challenges [player2] to a thumb war!"))
		if(!do_after(player1, 5 SECONDS, target = player2))
			player2.visible_message(span_notice("The players cancelled their thumb war!"))
			return 0
		if(!hand_games_check(player1,player2))
			return
		if(prob(50))
			player1.visible_message(span_notice("After a gruelling battle, [player1] eventually manages to subdue the thumb of [player2]!"))
		else
			player2.visible_message(span_notice("After a gruelling battle, [player2] eventually manages to subdue the thumb of [player1]!"))

///Play dead for sparkledog memes

/mob/living/carbon/human/proc/play_dead()
	set name = "Play Dead"
	set desc = "Literally just die on the spot. It's okay, you can get better."
	set category = "Abilities.Sparkledog"

	if(stat)
		to_chat(src, span_warning("You're too messed up right now to act all messed up, it's, like, for real."))
		return

	if(!resting)
		SetResting(1)
		add_modifier(/datum/modifier/play_dead, null, src) //Tracks whether they are still resting to remove the status indicator
		add_status_indicator("dead")
		visible_message(span_warning("\The [src] literally just dies!"))
	else
		SetResting(0)

/datum/modifier/play_dead
	name = "playing dead"
	desc = "You are are pretending to be dead, you aren't very convincing!"
	on_created_text = span_notice("You begin to play dead!")
	on_expired_text = span_notice("You got better.")

/datum/modifier/play_dead/tick()
	if(!holder.resting)
		expire()

/datum/modifier/play_dead/expire()
	holder.remove_status_indicator("dead")
	holder.visible_message(span_warning("\The [src] literally just dies!"))
	..()
