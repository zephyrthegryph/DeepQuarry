///////////////////// Simple Animal /////////////////////
/mob/living/simple_mob
	var/swallowTime = (3 SECONDS)		//How long it takes to eat its prey in 1/10 of a second. The default is 3 seconds.
	var/list/prey_excludes = null		//For excluding people from being eaten (a relation list: a deleted mob leaves it).

/mob/living/simple_mob/insidePanel() //On-demand belly loading.
	if(vore_active && !voremob_loaded)
		init_vore(TRUE)
	..()

// Simple nom proc for if you get ckey'd into a simple_mob mob! Avoids grabs.
/mob/living/simple_mob/proc/animal_nom(mob/living/T in living_mobs_in_view(1))
	set name = "Animal Nom"
	set category = VERB_CAT_ABILITIES_VORE // Moving this to abilities from IC as it's more fitting there
	set desc = "Since you can't grab, you get a verb!"

	if(vore_active && !voremob_loaded) // On-demand belly loading.
		init_vore(TRUE)

	if(stat != CONSCIOUS)
		return
	// Verbs are horrifying. They don't call overrides. So we're stuck with this.
	if(istype(src, /mob/living/simple_mob/animal/passive/mouse) && !T.ckey)
		// Mice can't eat logged out players!
		return
	/*if(client && IsAdvancedToolUser()) Mob QOL, not everything can be grabbed and nobody wants wiseguy gotchas for trying.
		to_chat(src, span_warning("Put your hands to good use instead!"))
		return
	*/
	feed_grabbed_to_self(src,T)

/mob/living/simple_mob/perform_the_nom(mob/living/user, mob/living/prey, mob/living/pred, obj/belly/belly, delay_time)
	if(vore_active && !voremob_loaded && pred == src) //Only init your own bellies.
		init_vore(TRUE)
		belly = vore_selected
	return ..()

/mob/living/simple_mob/begin_instant_nom(mob/living/user, mob/living/prey, mob/living/pred, obj/belly/belly)
	if(vore_active && !voremob_loaded && pred == src) //Only init your own bellies.
		init_vore(TRUE)
		belly = vore_selected
	return ..()
// Simple proc for animals to have their digestion toggled on/off externally
// Added as a verb in /mob/living/simple_mob/init_vore() if vore is enabled for this mob.
/mob/living/simple_mob/proc/toggle_digestion()
	set name = "Toggle Animal's Digestion"
	set desc = "Enables digestion on this mob for 20 minutes."
	set category = VERB_CAT_OOC_MOB_SETTINGS
	set src in oview(1)

	return toggle_digestion_for(usr)

/mob/living/simple_mob/proc/toggle_digestion_for(mob/living/carbon/human/user)
	return toggle_digestion_stage(user, null, null)

/mob/living/simple_mob/proc/toggle_digestion_stage(mob/living/carbon/human/user, enable_answer, disable_answer)
	if(!istype(user) || user.stat) return

	if(!vore_selected)
		to_chat(user, span_warning("[src] isn't planning on eating anything much less digesting it."))
		return

	if(vore_selected.digest_mode == DM_HOLD)
		if(isnull(enable_answer))
			open_request(src, /datum/prompt/choice/animal_digestion/enable, PROC_REF(animal_digestion_answered), answerer = user, question = "Enabling digestion on [name] will cause it to digest all stomach contents. Using this to break OOC prefs is against the rules. Digestion will reset after 20 minutes.", title = "Enabling [name]'s Digestion", enable_answer = enable_answer, disable_answer = disable_answer)
			return
		if(enable_answer == "Enable")
			vore_selected.digest_mode = DM_DIGEST
			after(vore_selected, 20 MINUTES, TYPE_PROC_REF(/obj/belly, reset_digest_mode), with = list(vore_default_mode))
	else
		if(isnull(disable_answer))
			open_request(src, /datum/prompt/choice/animal_digestion/disable, PROC_REF(animal_digestion_answered), answerer = user, question = "This mob is currently set to process all stomach contents. Do you want to disable this?", title = "Disabling [name]'s Digestion", enable_answer = enable_answer, disable_answer = disable_answer)
			return
		if(disable_answer == "Disable")
			vore_selected.digest_mode = DM_HOLD

// Added as a verb in /mob/living/simple_mob/init_vore() if vore is enabled for this mob.
/mob/living/simple_mob/proc/toggle_fancygurgle()
	set name = "Toggle Animal's Gurgle sounds"
	set desc = "Switches between Fancy and Classic sounds on this mob."
	set category = VERB_CAT_OOC_MOB_SETTINGS
	set src in oview(1)

	var/mob/living/user = usr	//I mean, At least ghosts won't use it.
	if(!istype(user) || user.stat) return
	if(!vore_selected)
		to_chat(user, span_warning("[src] isn't vore capable."))
		return

	vore_selected.fancy_vore = !vore_selected.fancy_vore
	to_chat(user, "[src] is now using [vore_selected.fancy_vore ? "Fancy" : "Classic"] vore sounds.")

/mob/living/simple_mob/hit_with_item(obj/item/O, mob/user, attack_modifier)
	if(istype(O, /obj/item/newspaper) && !(ckey || (ai_brain && ai_brain.hostile && faction != user.faction)) && isturf(user.loc))
		//legacy `.retaliate` is dead — every brain mob fights back on
		// provocation. Gate stays on brain presence + the existing coin flip.
		if(ai_brain && prob(vore_pounce_chance/2)) // This is a gamble!
			user.status_at_least(STAT_WEAKENED, 5) //They get tackled anyway whether they're edible or not.
			act_message(user, src, others = span_danger("%U% swats %T% with [O] and promptly gets tackled!"))
			if(will_eat(user))
				ai_busy_begin()
				animal_nom(user)
				update_icon()
				ai_busy_end()
			//legacy give_target call on attack/feed removed; brain handles auto-targeting.
		else
			act_message(user, src, others = span_info("%U% swats %T% with [O]!"))
			release_vore_contents()
			for(var/mob/living/L in living_mobs(0)) //add everyone on the tile to the do-not-eat list for a while
				if(!(LAZYFIND(prey_excludes, L))) // Unless they're already on it, just to avoid fuckery.
					rel_add(src, nameof(prey_excludes), L)
					after(src, 5 MINUTES, PROC_REF(removeMobFromPreyExcludes), with = list(L))
	else if(istype(O, /obj/item/healthanalyzer))
		var/healthpercent = round(vitality() * 100)
		to_chat(user, span_notice("[src] seems to be [healthpercent]% healthy."))
	else
		..()

/mob/living/simple_mob/proc/removeMobFromPreyExcludes(mob/living/L)
	// The timer skips a deleted L: prey_excludes is a relation list, so it already left.
	rel_remove(src, nameof(prey_excludes), L)

/mob/living/simple_mob/proc/nutrition_heal()
	set name = "Nutrition Heal"
	set category = VERB_CAT_ABILITIES_MOB
	set desc = "Slowly regenerate health using nutrition."

	return nutrition_heal_stage(null)

/mob/living/simple_mob/proc/nutrition_heal_stage(heal_amount)
	if(nutrition < 10)
		to_chat(src, span_warning("You are too hungry to regenerate health."))
		return
	var/endurance_now = get_endurance()
	if(isnull(heal_amount))
		open_request(src, /datum/prompt/number/animal_nutrition_heal, PROC_REF(animal_nutrition_heal_answered), answerer = src, question = "Input the amount of health to regenerate at the rate of 10 nutrition per second per hitpoint. Current health: [round(vitality() * endurance_now)] / [endurance_now]")
		return
	if(!heal_amount)
		return
	var/missing = round((1 - vitality()) * get_endurance()) // re-read after the input prompt
	heal_amount = CLAMP(heal_amount, 1, max(1, missing))
	heal_amount = CLAMP(heal_amount, 1, nutrition / 10)
	om_task_timed(src, 10 * heal_amount, null, src, PROC_REF(nutrition_heal_done), list(heal_amount))

/mob/living/simple_mob/proc/nutrition_heal_done(heal_amount)
	adjust_nutrition(-(10 * heal_amount))
	// Spend the budget mechanism by mechanism, in the old brute > burn > oxy > tox > clone order.
	// Plating/wiring cover synthetic bodies; the body ignores tags that don't match its biology.
	for(var/treat_tag in list(TREAT_TISSUE_REPAIR, TREAT_PLATING_REPAIR, TREAT_BURN_CARE, TREAT_WIRING_REPAIR, TREAT_OXYGENATION, TREAT_ANTITOXIN, TREAT_GENETIC_REPAIR))
		if(heal_amount <= 0)
			break
		heal_amount -= mend(treat_tag, heal_amount)

/mob/living/simple_mob/relations()
	. = ..()
	. += rel_many(nameof(prey_excludes))

/// Both cached branch answers survive a mode change while a digestion question is pending.
/datum/prompt/choice/animal_digestion
	timeout = 0
	buttons = TRUE
	var/enable_answer
	var/disable_answer
	var/enabling = FALSE

/datum/prompt/choice/animal_digestion/enable
	choices = list("Enable", "Cancel")
	enabling = TRUE

/datum/prompt/choice/animal_digestion/disable
	choices = list("Disable", "Cancel")

/mob/living/simple_mob/proc/animal_digestion_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = animal_digestion_apply(A)
	SStgui.update_uis(src)
	return .

/mob/living/simple_mob/proc/animal_digestion_apply(datum/act/request/A)
	var/datum/prompt/choice/animal_digestion/ask = A.answer
	var/enable_answer = ask.enable_answer
	var/disable_answer = ask.disable_answer
	if(ask.enabling)
		enable_answer = ask.value
	else
		disable_answer = ask.value
	return toggle_digestion_stage(ask.answerer, enable_answer, disable_answer)

/datum/prompt/number/animal_nutrition_heal
	title = "Regenerate health."
	timeout = 0
	default = 1
	min_value = 1
	max_value = INFINITY

/mob/living/simple_mob/proc/animal_nutrition_heal_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = nutrition_heal_stage(A.answer.value)
	SStgui.update_uis(src)
	return .
