///////////////////// Simple Animal /////////////////////
/mob/living/simple_mob
	var/swallowTime = (3 SECONDS)		//How long it takes to eat its prey in 1/10 of a second. The default is 3 seconds.
	var/list/prey_excludes = null		//For excluding people from being eaten.

/mob/living/simple_mob/insidePanel() //On-demand belly loading.
	if(vore_active && !voremob_loaded)
		init_vore(TRUE)
	..()

// Simple nom proc for if you get ckey'd into a simple_mob mob! Avoids grabs.
/mob/living/simple_mob/proc/animal_nom(mob/living/T in living_mobs_in_view(1))
	set name = "Animal Nom"
	set category = "Abilities.Vore" // Moving this to abilities from IC as it's more fitting there
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
	set category = "OOC.Mob Settings"
	set src in oview(1)

	var/mob/living/carbon/human/user = usr
	if(!istype(user) || user.stat) return

	if(!vore_selected)
		to_chat(user, span_warning("[src] isn't planning on eating anything much less digesting it."))
		return

	if(vore_selected.digest_mode == DM_HOLD)
		var/confirm = rerun_prompt(user, "a1", list("message" = "Enabling digestion on [name] will cause it to digest all stomach contents. Using this to break OOC prefs is against the rules. Digestion will reset after 20 minutes.", "title" = "Enabling [name]'s Digestion", "choices" = list("Enable", "Cancel")), PROC_REF(toggle_digestion), args)
		if(isnull(confirm))
			return
		if(confirm == "Enable")
			vore_selected.digest_mode = DM_DIGEST
			om_after(vore_selected, 20 MINUTES, TYPE_PROC_REF(/obj/belly, reset_digest_mode), vore_default_mode)
	else
		var/confirm = rerun_prompt(user, "a2", list("message" = "This mob is currently set to process all stomach contents. Do you want to disable this?", "title" = "Disabling [name]'s Digestion", "choices" = list("Disable", "Cancel")), PROC_REF(toggle_digestion), args)
		if(isnull(confirm))
			return
		if(confirm == "Disable")
			vore_selected.digest_mode = DM_HOLD

// Added as a verb in /mob/living/simple_mob/init_vore() if vore is enabled for this mob.
/mob/living/simple_mob/proc/toggle_fancygurgle()
	set name = "Toggle Animal's Gurgle sounds"
	set desc = "Switches between Fancy and Classic sounds on this mob."
	set category = "OOC.Mob Settings"
	set src in oview(1)

	var/mob/living/user = usr	//I mean, At least ghosts won't use it.
	if(!istype(user) || user.stat) return
	if(!vore_selected)
		to_chat(user, span_warning("[src] isn't vore capable."))
		return

	vore_selected.fancy_vore = !vore_selected.fancy_vore
	to_chat(user, "[src] is now using [vore_selected.fancy_vore ? "Fancy" : "Classic"] vore sounds.")

/mob/living/simple_mob/attackby(obj/item/O, mob/user)
	if(istype(O, /obj/item/newspaper) && !(ckey || (ai_brain && ai_brain.hostile && faction != user.faction)) && isturf(user.loc))
		//legacy `.retaliate` is dead — every brain mob fights back on
		// provocation. Gate stays on brain presence + the existing coin flip.
		if(ai_brain && prob(vore_pounce_chance/2)) // This is a gamble!
			user.status_at_least(EFFECT_WEAKENED, 5) //They get tackled anyway whether they're edible or not.
			user.visible_message(span_danger("[user] swats [src] with [O] and promptly gets tackled!"))
			if(will_eat(user))
				ai_busy_begin()
				animal_nom(user)
				update_icon()
				ai_busy_end()
			//legacy give_target call on attack/feed removed; brain handles auto-targeting.
		else
			user.visible_message(span_info("[user] swats [src] with [O]!"))
			release_vore_contents()
			for(var/mob/living/L in living_mobs(0)) //add everyone on the tile to the do-not-eat list for a while
				if(!(LAZYFIND(prey_excludes, L))) // Unless they're already on it, just to avoid fuckery.
					LAZYSET(prey_excludes, L, world.time)
					om_after(src, 5 MINUTES, PROC_REF(removeMobFromPreyExcludes), om_handle(L))
	else if(istype(O, /obj/item/healthanalyzer))
		var/healthpercent = round(vitality() * 100)
		to_chat(user, span_notice("[src] seems to be [healthpercent]% healthy."))
	else
		..()

/mob/living/simple_mob/proc/removeMobFromPreyExcludes(target)
	if(om_is_handle(target))
		var/mob/living/L = om_resolve(target)
		LAZYREMOVE(prey_excludes, L) // It's fine to remove a null from the list if we couldn't resolve L

/mob/living/simple_mob/proc/nutrition_heal()
	set name = "Nutrition Heal"
	set category = "Abilities.Mob"
	set desc = "Slowly regenerate health using nutrition."

	if(nutrition < 10)
		to_chat(src, span_warning("You are too hungry to regenerate health."))
		return
	var/endurance_now = get_endurance()
	var/heal_amount = rerun_prompt(src, "a3", list("kind" = "number", "message" = "Input the amount of health to regenerate at the rate of 10 nutrition per second per hitpoint. Current health: [round(vitality() * endurance_now)] / [endurance_now]", "title" = "Regenerate health.", "default" = 1, "min" = 1), PROC_REF(nutrition_heal), args)
	if(isnull(heal_amount))
		return
	if(!heal_amount)
		return
	var/missing = round((1 - vitality()) * get_endurance()) // re-read after the input prompt
	heal_amount = CLAMP(heal_amount, 1, max(1, missing))
	heal_amount = CLAMP(heal_amount, 1, nutrition / 10)
	om_do_after(src, 10 * heal_amount, null, src, PROC_REF(nutrition_heal_done), list(heal_amount))

/mob/living/simple_mob/proc/nutrition_heal_done(heal_amount)
	nutrition -= 10 * heal_amount
	// Spend the budget mechanism by mechanism, in the old brute > burn > oxy > tox > clone order.
	// Plating/wiring cover synthetic bodies; the body ignores tags that don't match its biology.
	for(var/treat_tag in list(TREAT_TISSUE_REPAIR, TREAT_PLATING_REPAIR, TREAT_BURN_CARE, TREAT_WIRING_REPAIR, TREAT_OXYGENATION, TREAT_ANTITOXIN, TREAT_GENETIC_REPAIR))
		if(heal_amount <= 0)
			break
		heal_amount -= mend(treat_tag, heal_amount)
