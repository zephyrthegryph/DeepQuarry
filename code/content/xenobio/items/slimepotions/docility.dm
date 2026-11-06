// Makes the slime friendly forever.
/obj/item/slimepotion/docility/get_mechanics_info(list/additional_information)
	return ..(list("The target needs to be alive, not already passive, and be an animal or slime type entity.") + additional_information)

/obj/item/slimepotion/docility
	name = "slime docility agent"
	desc = "A potent chemical mix that nullifies a slime's hunger, causing it to become docile and tame.  It might also work on other creatures?"
	icon_state = "potlightpink"
	var/currently_using = FALSE						// To avoid same potion being usable multiple times

/obj/item/slimepotion/docility/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!istype(M, /mob/living/simple_mob))
		to_chat(user, span_warning("The agent only works on creatures!"))
		return ..()
	if(M.stat == DEAD)
		to_chat(user, span_warning("\The [M] is dead!"))
		return ..()
	if(!(M.ai_brain != null))
		to_chat(user, span_warning("\The [M] is too strongly willed for this to affect them.")) // Most likely player controlled.
		return
	if(currently_using)
		to_chat(user, span_warning("This agent has already been used!")) // Possibly trying to cheese the dialogue box and use same potion on multiple targets.
		return ITEM_INTERACT_FAILURE

	currently_using = TRUE
	var/datum/ai_brain/AI = M.ai_brain

	// Slimes.
	if(istype(M, /mob/living/simple_mob/slime/xenobio))
		var/mob/living/simple_mob/slime/xenobio/S = M
		if(S.harmless)
			to_chat(user, span_warning("The slime is already docile!"))
			currently_using = FALSE
			return ..()

		S.pacify()
		S.set_nutrition(700)
		to_chat(M, span_warning("You absorb the agent and feel your intense desire to feed melt away."))
		to_chat(user, span_notice("You feed the slime the agent, removing its hunger and calming it."))

	// Simple Mobs.
	else if(isanimal(M))
		var/mob/living/simple_mob/SM = M
		if(!(kind_of(SM).mob_class & (MOB_CLASS_SLIME|MOB_CLASS_ANIMAL))) // So you can't use this on Russians/syndies/hivebots/etc.
			to_chat(user, span_warning("\The [src] only works on slimes and animals."))
			currently_using = FALSE
			return ..()
		if(!AI.hostile)
			to_chat(user, span_warning("\The [SM] is already passive!"))
			currently_using = FALSE
			return ..()

		//legacy .hostile reference removed (no equivalent on /datum/ai_brain).
		to_chat(M, span_warning("You consume the agent and feel a serene sense of peace."))
		to_chat(user, span_notice("You feed \the [SM] the agent, calming it."))

	play_sfx(src, SFX_EFFECTS_BUBBLES)
	AI.remove_target() // So hostile things stop attacking people even if not hostile anymore.
	open_request(src, /datum/prompt/text/slime_docility_name, PROC_REF(docility_name_entered), answerer = user, subject = M, default = M.name, question = "Would you like to give \the [M] a name?")
	return TRUE

/obj/item/slimepotion/docility/proc/docility_name_entered(datum/act/request/A)
	if(isnull(A.request.value) || A.request.last_error == "gone")
		return
	SStgui.update_uis(src)
	var/mob/living/M = A.request.subject
	var/mob/living/user = A.request.answerer
	if(!A.answer)
		if(A.request.last_error == "dead")
			to_chat(user, span_warning("\The [M] is dead!"))
		else if(A.request.last_error == "no brain")
			to_chat(user, span_warning("\The [M] is too strongly willed for this to affect them."))
		return
	var/newname = copytext(A.answer.value,1,MAX_NAME_LEN)
	if(newname && !QDELETED(M))
		M.name = newname
		M.set_real_name(newname)
	consume(src, user)
