///// A mob that gets used when prey dominate predators. Will automatically delete itself if it's not inside a mob.

/mob/living/dominated_brain
	name = "dominated brain"
	desc = "Someone who has taken a back seat within their own body."
	icon = 'icons/obj/surgery.dmi'
	icon_state = "brain1"
	forced_psay = TRUE
	var/mob/living/prey_body		//The body of the person who dominated the brain
	/// The prey's mind. It carries the prey's identity wherever it goes.
	var/datum/mind/prey_mind
	var/prey_name					//In case the body is missing. ;3c
	var/list/prey_langs = list() // ALLOW(instance_list): d: per-mob prey_langs, filled at runtime; mobs are few
	var/mob/living/pred_body		//The body of the person who was dominated
	/// The predator's mind (null when the predator was an unplayed mob).
	var/datum/mind/pred_mind
	/// The predator had no mind: this back seat is kept even while empty.
	var/was_mob

CAPABILITIES(/mob/living/dominated_brain)
	op("resist_control", menu(button = "Resist Control"), when(PROC_REF(resisting_control)), starts(PROC_REF(resist_control_started)), wait(10 SECONDS), then(PROC_REF(resist_control_done)), on_interrupt(PROC_REF(resist_control_interrupted)))
	op("resist_control_dominate", menu(button = "Resist Control"), when(PROC_REF(dominating_predator)), then(PROC_REF(resist_control_dominate)))
	op("return_to_body", menu(button = "Return to Body"), when(PROC_REF(body_is_here)), starts(PROC_REF(return_to_body_started)), wait(10 SECONDS), then(PROC_REF(return_to_body_done)), on_interrupt(PROC_REF(return_to_body_interrupted)))
	param(nameof(pred_body), pos = 1)
	param(nameof(prey_name), pos = 2)
	param(nameof(prey_body), pos = 3, apply = PROC_REF(take_seat))

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm). A dominated brain exists only inside a living body.
/mob/living/dominated_brain/proc/take_seat(prey)
	if(!isliving(loc))
		spent(src)
		return
	lets_register_our_signals()

/mob/living/dominated_brain/life_type_post_due()
	return TRUE

/mob/living/dominated_brain/life_type_post(datum/seq_frame/life/F)
	..()
	if(!isliving(src.loc))
		spent(src)
		return
	if(!src.mind && !src.was_mob)
		spent(src)

/mob/living/dominated_brain/say_understands(mob/other, datum/language/speaking = null)
	if(pred_body.say_understands(other, speaking))
		return TRUE
	else return FALSE

/mob/living/dominated_brain/proc/lets_register_our_signals()
	if(prey_body)
		global.observe(prey_body, /datum/notice/qdeleting, src, then(PROC_REF(prey_was_deleted)))
	global.observe(pred_body, /datum/notice/qdeleting, src, then(PROC_REF(pred_was_deleted)))

/mob/living/dominated_brain/proc/lets_unregister_our_signals()
	prey_was_deleted()
	pred_was_deleted()

/// Also called directly with no args (lets_unregister_our_signals).
/mob/living/dominated_brain/proc/prey_was_deleted(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	if(prey_body)
		unobserve(prey_body, /datum/notice/qdeleting, src)
		rel_clear(src, nameof(prey_body))

/// Also called directly with no args (lets_unregister_our_signals).
/mob/living/dominated_brain/proc/pred_was_deleted(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	if(pred_body)
		unobserve(pred_body, /datum/notice/qdeleting, src)
		rel_clear(src, nameof(pred_body))

/// A no-first confirmation; only Yes invokes the original continuation.
/datum/prompt/choice/dominated_brain_confirm
	buttons = TRUE
	timeout = 0

/datum/prompt/choice/dominated_brain_confirm/prepare(datum/act/A)
	..()
	var/static/list/confirmation_buttons = list("No", "Yes")
	choices = confirmation_buttons

/mob/living/dominated_brain/process_resist()
	//Resisting control by an alien mind.
	if(pred_mind && pred_body.mind == pred_mind)
		dominate_predator()
		return
	if(mind == pred_mind && pred_body.prey_controlled)
		open_request(src, /datum/prompt/choice/dominated_brain_confirm, PROC_REF(resist_domination_confirmed), answerer = src, title = "Regain Control", question = "Do you want to wrest control over your body back from \the [prey_name]?")
	else
		to_chat(src, span_warning("\The [pred_body] is already dominated, and cannot be controlled at this time."))
		..()

/mob/living/dominated_brain/proc/resist_domination_confirmed(datum/act/request/A)
	if(!A.answer || A.answer.value != "Yes")
		return
	perform_op(src, src, "resist_control", null, ORIGIN_VERB, AUTH_PHYSICAL)

/// The "resist_control" op is offered while a predator's mind holds this brain's body and this brain wields it.
/mob/living/dominated_brain/proc/resisting_control(datum/act/op/A)
	return read_once(!(pred_mind && pred_body.mind == pred_mind) && mind == pred_mind && pred_body.prey_controlled)

/// The "resist_control_dominate" op is offered while the predator's mind is in its own body (resisting means dominating it back).
/mob/living/dominated_brain/proc/dominating_predator(datum/act/op/A)
	return read_once(pred_mind && pred_body.mind == pred_mind)

/mob/living/dominated_brain/proc/resist_control_dominate(datum/act/op/A)
	dominate_predator()

/mob/living/dominated_brain/proc/resist_control_started(datum/act/op/A)
	to_chat(src, span_danger("You begin to resist \the [prey_name]'s control!!!"))
	to_chat(pred_body, span_danger("You feel the captive mind of [src] begin to resist your control."))

/mob/living/dominated_brain/proc/resist_control_done(datum/act/op/A)
	restore_control()

/mob/living/dominated_brain/proc/resist_control_interrupted(datum/act/op/A)
	to_chat(src, span_notice("Your attempt to regain control has been interrupted..."))
	to_chat(pred_body, span_notice("The dominant sensation fades away..."))

/mob/living/dominated_brain/proc/restore_control(ask = TRUE)

	if(ask && disconnect_time || client && ((client.inactivity / 10) / 60 > 10))
		open_request(src, /datum/prompt/choice/dominated_brain_confirm, PROC_REF(restore_control_confirmed), answerer = src, title = "Release Control", question = "Your predator's mind does not seem to be active presently. Releasing control in this state may leave you stuck in whatever state you find yourself in. Are you sure?")
		return
	restore_control_now()

/mob/living/dominated_brain/proc/restore_control_confirmed(datum/act/request/A)
	if(!A.answer || A.answer.value != "Yes")
		return
	restore_control_now()

/mob/living/dominated_brain/proc/restore_control_now()
	if(!pred_body)
		return
	var/mob/living/prey_goes_here

	if(prey_body && prey_body.loc.loc == pred_body)	//The prey body exists and is here, let's handle the prey!

		prey_goes_here = prey_body

	else if(prey_body)	//It exists, but it's not here, let's spawn them a temporary home.
		var/mob/living/dominated_brain/ndb = new /mob/living/dominated_brain(pred_body, pred_body, prey_name, prey_body)
		ndb.name = prey_name
		rel_set(ndb, nameof(ndb.prey_mind), prey_mind)
		rel_set(ndb, nameof(ndb.pred_mind), pred_mind)

		prey_goes_here = ndb
		prey_goes_here.real_name = src.prey_name
		src.languages -= src.temp_languages
		prey_goes_here.languages |= src.prey_langs

	else		//The prey body does not exist, let's put them in the back seat instead!
		var/mob/living/dominated_brain/ndb = new /mob/living/dominated_brain(pred_body, pred_body, prey_name)
		ndb.name = prey_name
		rel_set(ndb, nameof(ndb.prey_mind), prey_mind)
		rel_set(ndb, nameof(ndb.pred_mind), pred_mind)

		prey_goes_here = ndb
		src.languages -= src.temp_languages
		prey_goes_here.languages |= src.prey_langs
		prey_goes_here.real_name = src.prey_name

	///////////////////

	// Handle Pred
	revoke(pred_body, granted_verb(/mob/proc/release_predator), pred_body)

	//Now actually put the people in the mobs. The prey wears its own identity
	//in a back seat and binds it again in its own body; the predator gets its
	//body back.
	var/datum/mind/returning_prey = prey_mind
	var/datum/mind/returning_pred = pred_mind
	move_player_mind(returning_prey, prey_goes_here, "prey domination of [pred_body] ended", share = (prey_goes_here != prey_body))
	move_player_mind(returning_pred, pred_body, "regained control of own body from [prey_name]")
	log_and_message_admins("is now controlled by [pred_body.ckey]. They were restored to control through prey domination, and had been controlled by [returning_prey?.key].", pred_body)
	pred_body.absorb_langs()
	pred_body.prey_controlled = FALSE
	dissolved(src)

/mob/living/proc/absorb_langs()		//This should be called on the predator in the exchange
	var/list/langlist = list()

	languages -= temp_languages
	LAZYCLEARLIST(src.temp_languages)
	for(var/mob/living/L in contents)
		if(istype(L,/mob/living/dominated_brain))
			if(L.ckey)
				langlist |= L.languages
	for(var/b in vore_organs)
		for(var/mob/living/L in b)
			if(isliving(L))
				if(L.ckey)
					langlist |= L.languages
	if(langlist.len)
		langlist -= languages
		for(var/datum/language/L in langlist)
			if(L.flags & HIVEMIND)
				grant(src, granted_verb(/mob/proc/adjust_hive_range), src)
		LAZYOR(temp_languages, langlist)
		languages |= langlist

//Welcome to the adapted borer code.
/mob/proc/dominate_predator()
	set category = VERB_CAT_ABILITIES_VORE
	set name = "Dominate Predator"
	set desc = "Connect to and dominate the brain of your predator."

	var/mob/living/pred
	var/mob/living/prey = src
	if(isbelly(prey.loc))
		pred = loc.loc
	else if(isliving(prey.loc))
		pred = loc
	else if(ispAI(src))
		var/mob/living/silicon/pai/pocketpal = src
		if(isbelly(pocketpal.card.loc))
			pred = pocketpal.card.loc.loc
	else
		to_chat(prey, span_notice("You are not inside anyone."))
		return

	if(prey.stat == DEAD)
		to_chat(prey, span_warning("You cannot do that in your current state."))
		return

	if(!pred.allow_mind_transfer)
		to_chat(prey, span_warning("[pred] is unable to be dominated."))
		return

	if(isrobot(pred) && jobban_isbanned(prey, JOB_CYBORG))
		to_chat(prey, span_warning("Forces beyond your comprehension forbid you from taking control of [pred]."))
		return
	if(prey.prey_controlled)
		to_chat(prey, span_warning("You are already controlling someone, you can't control anyone else at this time."))
		return
	if(pred.prey_controlled)
		to_chat(prey, span_warning("\The [pred] is already dominated, and cannot be controlled at this time."))
		return
	// The predator, when it's a player, consents twice.
	var/datum/control_transfer_review/dominate_predator/review = new
	rel_set(review, nameof(review.actor), src)
	rel_set(review, nameof(review.pred), pred)
	// The old last consent was included when the sequence was built, not when it resumed.
	review.ask_final = !!pred.ckey
	review.start()
	return TRUE

/// Native consent sequences keep their participants weak without adding gameplay gates.
/datum/control_transfer_review
	parent_type = /datum/prompt_workflow
	var/mob/actor

CAPABILITIES(/datum/control_transfer_review)
	ref_one(nameof(actor), /mob)

/datum/prompt/choice/control_transfer_review
	timeout = 0
	buttons = TRUE
	var/decline_text

/datum/prompt/choice/control_transfer_review/prepare(datum/act/A)
	..()
	var/static/list/confirmation_buttons = list("No", "Yes")
	choices = confirmation_buttons

/datum/prompt/choice/control_transfer_review/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/control_transfer_review/review = owner
	// A No ended the old prompt before the flow unparked its other captured participants.
	return value == "No" ? null : review.why_not()

/datum/control_transfer_review/proc/why_not()
	return QDELETED(actor) ? "gone" : null

/datum/control_transfer_review/proc/start()
	if(why_not())
		retire()
		return
	run_step(PROC_REF(start_step))

/datum/control_transfer_review/proc/start_step(datum/act/request/A)
	return

/datum/control_transfer_review/proc/run_step(step, datum/act/request/A)
	if(why_not())
		retire()
		return
	var/datum/result/result = safe_call(step, A)
	if(!result.ok)
		stack_trace("Control transfer step [step]: [result.error]")
		retire()

/datum/control_transfer_review/proc/ask(step, title, question, mob/user, decline_text)
	open_request(src, /datum/prompt/choice/control_transfer_review, step, answerer = user || actor, asker = actor, title = title, question = question, decline_text = decline_text)

/datum/control_transfer_review/proc/confirmed(datum/act/request/A, step)
	if(!A.answer || QDELETED(actor))
		retire()
		return
	if(A.answer.value == "No")
		var/datum/prompt/choice/control_transfer_review/question = A.request
		if(question.decline_text)
			to_chat(actor, span_warning("\The [question.answerer] [question.decline_text]"))
		retire()
		return
	run_step(step, A)

/datum/control_transfer_review/dominate_predator
	var/mob/living/pred
	var/ask_final = FALSE

CAPABILITIES(/datum/control_transfer_review/dominate_predator)
	ref_one(nameof(pred), /mob/living)

/datum/control_transfer_review/dominate_predator/why_not()
	. = ..()
	if(.)
		return
	return QDELETED(pred) ? "gone" : null

/datum/control_transfer_review/dominate_predator/start_step(datum/act/request/A)
	ask(PROC_REF(sure_entered), "Take Over Predator", "You are attempting to take over [pred], are you sure? Ensure that their preferences align with this kind of play.")

/datum/control_transfer_review/dominate_predator/proc/sure_entered(datum/act/request/A)
	confirmed(A, PROC_REF(offer_step))

/datum/control_transfer_review/dominate_predator/proc/offer_step(datum/act/request/A)
	to_chat(actor, span_notice("You attempt to exert your control over \the [pred]..."))
	log_admin("[key_name_admin(actor)] attempted to take over [pred].")
	if(!pred.ckey)
		final_offer_step()
		return
	ask(PROC_REF(offer_entered), "Allow Prey Domination", "\The [actor] has elected to attempt to take control of you. Is this something you will allow to happen?", pred, "declined your request for control.")

/datum/control_transfer_review/dominate_predator/proc/offer_entered(datum/act/request/A)
	confirmed(A, PROC_REF(final_offer_step))

/datum/control_transfer_review/dominate_predator/proc/final_offer_step(datum/act/request/A)
	if(!ask_final)
		finish_step()
		return
	ask(PROC_REF(final_entered), "Allow Prey Domination", "Are you sure? If you should decide to revoke this, you will have the ability to do so in your 'Abilities' tab.", pred)

/datum/control_transfer_review/dominate_predator/proc/final_entered(datum/act/request/A)
	confirmed(A, PROC_REF(finish_step))

/datum/control_transfer_review/dominate_predator/proc/finish_step(datum/act/request/A)
	actor.dominate_predator_agreed(src)
	retire()

/mob/proc/dominate_predator_agreed(datum/control_transfer_review/dominate_predator/seq)
	var/mob/living/prey = src
	var/mob/living/pred = seq.pred
	if(prey.stat == DEAD || prey.prey_controlled || pred.prey_controlled || !pred.allow_mind_transfer)
		return
	if(!pred.client && ("original_player" in pred.vars)) //check if the body belonged to a player and give proper log about it while preparing it
		log_and_message_admins("[key_name_admin(prey)] is taking control over [pred] while they are out of their body.")

	to_chat(pred, span_warning("You can feel the will of another overwriting your own, control of your body being sapped away from you..."))
	to_chat(prey, span_warning("You can feel the will of your host diminishing as you exert your will over them!"))
	perform_op(prey, pred, "dominate_predator", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL)
	return TRUE

/// The dominate op runs on the predator (src); the prey that dominates it is the actor.
/mob/living/proc/dominate_predator_done(datum/act/op/A)
	var/mob/living/pred = src
	var/mob/living/prey = A.actor
	if(QDELETED(prey))
		return OP_FAILED
	to_chat(prey, span_danger("You plunge your conciousness into \the [pred], assuming control over their very body, leaving your own behind within \the [pred]'s [prey.loc]."))
	to_chat(pred, span_danger("You feel your body move on its own, as you are pushed to the background, and an alien consciousness displaces yours."))
	take_over_predator(prey, pred, "prey domination")
	return OP_OK

/mob/living/proc/dominate_predator_failed(datum/act/op/A)
	var/mob/living/pred = src
	var/mob/living/prey = A.actor
	to_chat(prey, span_notice("Your attempt to regain control has been interrupted..."))
	to_chat(pred, span_notice("The dominant sensation fades away..."))
	return OP_OK

/mob/proc/release_predator()
	set category = VERB_CAT_ABILITIES_VORE
	set name = "Restore Control"
	set desc = "Release control of your predator's body."

	for(var/I in contents)
		if(istype(I, /mob/living/dominated_brain))
			var/mob/living/dominated_brain/db = I
			if(db.mind == db.pred_mind)
				to_chat(src, span_notice("You ease off of your control, releasing \the [db]."))
				to_chat(db, span_notice("You feel the alien presence fade, and restore control of your body to you of their own will..."))
				db.restore_control()
				return
			else
				continue
	to_chat(src, span_danger("You haven't been taken over, and shouldn't have this verb. I'll clean that up for you. Report this on the github, it is a bug."))
	revoke(src, granted_verb(/mob/proc/release_predator), src)

/mob/living/proc/dominate_prey()
	set category = VERB_CAT_ABILITIES_VORE
	set name = "Dominate Prey"
	set desc = "Connect to and dominate the brain of your prey."

	var/list/possible_mobs = list()
	for(var/obj/belly/B in src.vore_organs)
		for(var/mob/living/L in B)
			if(isliving(L) && L.ckey && L.allow_mind_transfer)
				possible_mobs |= L
			else
				continue
	var/obj/item/grab/G = src.get_active_hand()
	if(istype(G))
		var/mob/living/L = G?.grab_target()
		if(istype(L) && L.allow_mind_transfer)
			if(G.state != GRAB_NECK)
				possible_mobs |= "~~[L.name]~~ (reinforce grab first)"
			else
				possible_mobs |= L
	if(!possible_mobs)
		to_chat(src, span_warning("There are no valid targets inside of you."))
		return
	var/datum/control_transfer_review/dominate_prey/review = new
	rel_set(review, nameof(review.actor), src)
	rel_set(review, nameof(review.grab), G)
	review.grab_selected = !isnull(G)
	review.choices = possible_mobs
	review.start()

/datum/control_transfer_review/dominate_prey
	var/mob/living/prey
	var/prey_selected = FALSE
	var/obj/item/grab/grab
	var/grab_selected = FALSE
	var/list/choices

CAPABILITIES(/datum/control_transfer_review/dominate_prey)
	ref_one(nameof(prey), /mob/living)
	ref_one(nameof(grab), /obj/item/grab)

/datum/prompt/choice/control_transfer_target
	timeout = 0
	title = "Dominate Prey"
	question = "Select a mob to dominate:"

/datum/prompt/choice/control_transfer_target/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/selected = value
	if(isdatum(selected) && QDELETED(selected))
		return "gone"
	var/datum/control_transfer_review/review = owner
	return review.why_not()

/datum/control_transfer_review/dominate_prey/why_not()
	. = ..()
	if(.)
		return
	if((prey_selected && QDELETED(prey)) || (grab_selected && QDELETED(grab)))
		return "gone"

/datum/control_transfer_review/dominate_prey/start_step(datum/act/request/A)
	open_request(src, /datum/prompt/choice/control_transfer_target, PROC_REF(target_entered), answerer = actor, asker = actor, choices = choices)

/datum/control_transfer_review/dominate_prey/proc/target_entered(datum/act/request/A)
	if(!A.answer)
		retire()
		return
	run_step(PROC_REF(target_step), A)

/datum/control_transfer_review/dominate_prey/proc/target_step(datum/act/request/A)
	var/mob/living/selected = A.answer.value
	if(!istype(selected))
		to_chat(actor, span_warning("You must have a tighter grip to dominate this creature."))
		retire()
		return
	rel_set(src, nameof(prey), selected)
	prey_selected = TRUE
	if(QDELETED(prey))
		retire()
		return
	if(!prey.allow_mind_transfer)
		to_chat(actor, span_warning("[prey] is unable to be dominated."))
		retire()
		return
	ask(PROC_REF(sure_entered), "Dominate Prey", "You selected [prey] to attempt to dominate. Are you sure?")

/datum/control_transfer_review/dominate_prey/proc/sure_entered(datum/act/request/A)
	confirmed(A, PROC_REF(offer_step))

/datum/control_transfer_review/dominate_prey/proc/offer_step(datum/act/request/A)
	log_admin("[key_name_admin(actor)] offered to use dominate prey on [prey] ([prey.ckey]).")
	to_chat(actor, span_warning("Attempting to dominate and gather \the [prey]'s mind..."))
	ask(PROC_REF(offer_entered), "Allow Dominate Prey", "\The [actor] has elected collect your mind into their own. Is this something you will allow to happen?", prey, "has declined your Dominate Prey attempt.")

/datum/control_transfer_review/dominate_prey/proc/offer_entered(datum/act/request/A)
	confirmed(A, PROC_REF(final_offer_step))

/datum/control_transfer_review/dominate_prey/proc/final_offer_step(datum/act/request/A)
	ask(PROC_REF(final_entered), "Allow Dominate Prey", "Are you sure? You can only undo this while your body is inside of [actor]. (You can resist, or use the resist verb in the abilities tab)", prey, "has declined your Dominate Prey attempt.")

/datum/control_transfer_review/dominate_prey/proc/final_entered(datum/act/request/A)
	confirmed(A, PROC_REF(finish_step))

/datum/control_transfer_review/dominate_prey/proc/finish_step(datum/act/request/A)
	var/mob/living/operator = actor
	operator.dominate_prey_agreed(src)
	retire()

/mob/living/proc/dominate_prey_agreed(datum/control_transfer_review/dominate_prey/seq)
	var/mob/living/M = seq.prey
	var/obj/item/grab/G = seq.grab
	if(!M.allow_mind_transfer)
		return
	to_chat(M, span_warning("You can feel the will of another pulling you away from your body..."))
	to_chat(src, span_warning("You can feel the will of your prey diminishing as you gather them!"))

	if(istype(G) && M == G?.grab_target())
		act_message(src, M, null, MSG_OTHERS(span_danger("%U% seems to be doing something to %T%, resulting in %T%'s body looking increasingly drowsy with every passing moment!")))
	perform_op(src, M, "dominate_prey", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("grab" = G))
	return TRUE

/// The gathering op runs on the prey (src); the one gathering is the actor.
/mob/living/proc/dominate_prey_done(datum/act/op/A)
	var/obj/item/grab/G = A.arg("grab")
	var/mob/living/gatherer = A.actor
	var/mob/living/M = src
	if(QDELETED(gatherer))
		return OP_FAILED
	if(!isbelly(M.loc) && !(istype(G) && M == G?.grab_target() && G.state == GRAB_NECK)) // Let dominate prey work on grabbed people
		to_chat(M, span_notice("The alien presence fades, and you are left along in your body..."))
		to_chat(gatherer, span_notice("Your attempt to gather [M]'s mind has been interrupted."))
		return OP_FAILED

	gatherer.gather_prey_mind(M)
	to_chat(gatherer, span_notice("You feel your mind expanded as [M] is incorporated into you."))
	to_chat(M, span_warning("Your mind is gathered into \the [gatherer], becoming part of them..."))
	if(istype(G) && M == G?.grab_target())
		act_message(gatherer, M, null, MSG_OTHERS(span_danger("%U% seems to finish whatever they were doing to %T%.")))
	return OP_OK

/mob/living/proc/dominate_prey_failed(datum/act/op/A)
	var/mob/living/M = src
	to_chat(M, span_notice("The alien presence fades, and you are left along in your body..."))
	to_chat(A.actor, span_notice("Your attempt to gather [M]'s mind has been interrupted."))
	return OP_OK

/// The "return_to_body" op is offered while this brain's body is inside the predator still.
/mob/living/dominated_brain/proc/body_is_here(datum/act/op/A)
	return read_once(prey_body && prey_body.loc.loc == pred_body)

/mob/living/dominated_brain/proc/return_to_body_started(datum/act/op/A)
	to_chat(src, span_notice("You exert your will and attempt to return to your body!!!"))
	to_chat(pred_body, span_warning("\The [src] resists your hold and attempts to return to their body!"))

/mob/living/dominated_brain/proc/return_to_body_done(datum/act/op/A)
	if(prey_body && prey_body.loc.loc == pred_body)
		return_to_body()
	else
		to_chat(src, span_warning("Your attempt to regain your body has been interrupted..."))

/mob/living/dominated_brain/proc/return_to_body_interrupted(datum/act/op/A)
	to_chat(src, span_warning("Your attempt to regain your body has been interrupted..."))

/mob/living/proc/lend_prey_control()
	set category = VERB_CAT_ABILITIES_VORE
	set name = "Give Prey Control"
	set desc = "Allow prey control of your body."

	var/list/possible_mobs = list()
	for(var/obj/belly/B in src.vore_organs)
		for(var/mob/living/L in B)
			if(isliving(L) && L.ckey)
				possible_mobs |= L
			else
				continue
	if(!possible_mobs)
		to_chat(src, span_warning("There are no valid targets inside of you."))
		return
	open_request(src, /datum/prompt/choice, PROC_REF(lend_prey_control_chosen), answerer = src, title = "Give Prey Control", question = "Select a mob to give control:", choices = possible_mobs, timeout = 0)

/// Whether we can hand our body to `prey` right now; says why not.
/mob/living/proc/can_lend_prey_control(mob/living/prey)
	var/mob/living/pred = src
	if(prey.stat == DEAD)
		to_chat(pred, span_warning("You cannot do that to this prey."))
		return FALSE
	if(!prey.ckey)
		to_chat(pred, span_notice("\The [prey] cannot take control."))
		return FALSE
	if(isrobot(pred) && jobban_isbanned(prey, JOB_CYBORG))
		to_chat(pred, span_warning("Forces beyond your comprehension prevent you from giving [prey] control."))
		return FALSE
	if(prey.prey_controlled)
		to_chat(pred, span_warning("\The [prey] is already under someone's control and cannot be given control of your body."))
		return FALSE
	if(pred.prey_controlled)
		to_chat(pred, span_warning("You are already controlling someone's body."))
		return FALSE
	return TRUE

/mob/living/proc/lend_prey_control_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/living/prey = A.answer.value
	if(!can_lend_prey_control(prey))
		return
	var/datum/control_transfer_review/lend_prey_control/review = new
	rel_set(review, nameof(review.actor), src)
	rel_set(review, nameof(review.prey), prey)
	review.start()

/datum/control_transfer_review/lend_prey_control
	var/mob/living/prey

CAPABILITIES(/datum/control_transfer_review/lend_prey_control)
	ref_one(nameof(prey), /mob/living)

/datum/control_transfer_review/lend_prey_control/why_not()
	. = ..()
	if(.)
		return
	return QDELETED(prey) ? "gone" : null

/datum/control_transfer_review/lend_prey_control/start_step(datum/act/request/A)
	ask(PROC_REF(sure_entered), "Give Prey Control", "You are attempting to give [prey] control over you, are you sure? Ensure that their preferences align with this kind of play.")

/datum/control_transfer_review/lend_prey_control/proc/sure_entered(datum/act/request/A)
	confirmed(A, PROC_REF(offer_step))

/datum/control_transfer_review/lend_prey_control/proc/offer_step(datum/act/request/A)
	to_chat(actor, span_notice("You attempt to give your control over to \the [prey]..."))
	log_admin("[key_name_admin(actor)] attempted to give control to [prey].")
	ask(PROC_REF(offer_entered), "Allow Prey Domination", "\The [actor] has elected to attempt to give you control of them. Is this something you will allow to happen?", prey, "declined your request for control.")

/datum/control_transfer_review/lend_prey_control/proc/offer_entered(datum/act/request/A)
	confirmed(A, PROC_REF(final_offer_step))

/datum/control_transfer_review/lend_prey_control/proc/final_offer_step(datum/act/request/A)
	ask(PROC_REF(final_entered), "Allow Prey Domination", "Are you sure? If you should decide to revoke this, you will have the ability to do so in your 'Abilities' tab.", prey)

/datum/control_transfer_review/lend_prey_control/proc/final_entered(datum/act/request/A)
	confirmed(A, PROC_REF(finish_step))

/datum/control_transfer_review/lend_prey_control/proc/finish_step(datum/act/request/A)
	var/mob/living/operator = actor
	operator.lend_prey_control_agreed(src)
	retire()

/mob/living/proc/lend_prey_control_agreed(datum/control_transfer_review/lend_prey_control/seq)
	var/mob/living/prey = seq.prey
	var/mob/living/pred = src
	if(!can_lend_prey_control(prey))
		return
	to_chat(pred, span_warning("You diminish your will, reducing it and allowing will of your prey to take over..."))
	to_chat(prey, span_warning("You can feel the will of your host diminishing as you are given control over them!"))
	perform_op(pred, prey, "lend_prey_control", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL)

/// The lending op runs on the prey (src); the predator that gives up control is the actor.
/mob/living/proc/lend_prey_control_done(datum/act/op/A)
	var/mob/living/prey = src
	var/mob/living/pred = A.actor
	if(QDELETED(pred))
		return OP_FAILED
	to_chat(prey, span_danger("You plunge your conciousness into \the [pred], assuming control over their very body, leaving your own behind within \the [pred]'s [pred.loc]."))
	to_chat(pred, span_danger("You feel your body move on its own, as you move to the background, and an alien consciousness displaces yours."))
	take_over_predator(prey, pred, "pred submission")
	return OP_OK

/mob/living/proc/lend_prey_control_failed(datum/act/op/A)
	var/mob/living/prey = src
	var/mob/living/pred = A.actor
	to_chat(pred, span_notice("Your attempt to share control has been interrupted..."))
	to_chat(prey, span_notice("The dominant sensation fades away..."))
	return OP_OK

/// The mind-move half of prey domination and pred submission: `prey`'s mind
/// takes `pred`'s body and the predator's mind (if any) moves into a back seat.
/// Both minds keep their own identity (shared, not bound) while in the other's
/// seat. Returns the back seat.
/proc/take_over_predator(mob/living/prey, mob/living/pred, method)
	var/mob/living/dominated_brain/pred_brain
	var/mob/living/dominated_brain/punished_prey = istype(prey, /mob/living/dominated_brain) ? prey : null
	if(punished_prey)
		//We have to play musical chairs with 3 bodies, or everyone gets d/ced
		pred_brain = new /mob/living/dominated_brain(pred, pred, prey.name, punished_prey.prey_body)
	else
		pred_brain = new /mob/living/dominated_brain(pred, pred, prey.name, prey)

	rel_set(pred_brain, nameof(pred_brain.prey_mind), prey.ensure_mind())
	rel_set(pred_brain, nameof(pred_brain.pred_mind), pred.mind)
	pred_brain.was_mob = isnull(pred_brain.pred_mind)
	pred_brain.name = pred.name
	pred_brain.real_name = pred.real_name
	var/list/preylangs = list()
	preylangs |= prey.languages
	preylangs -= prey.temp_languages
	pred_brain.prey_langs |= preylangs
	pred_brain.pred_body.absorb_langs()

	grant(pred, granted_verb(/mob/proc/release_predator), pred)

	move_player_mind(pred_brain.pred_mind, pred_brain, "pushed back by [prey] ([method])", share = TRUE)
	move_player_mind(pred_brain.prey_mind, pred, "took control of [pred] ([method])", share = TRUE)
	pred.prey_controlled = TRUE
	log_and_message_admins("is now controlled by [pred.ckey], they were taken over via [method], and were originally controlled by [pred_brain.pred_mind?.key].", pred)
	if(punished_prey)
		spent(punished_prey)
	return pred_brain

/// The mind-move half of dominate prey: `M`'s mind is gathered into a back
/// seat inside this predator, keeping its own identity. Returns the back seat.
/mob/living/proc/gather_prey_mind(mob/living/M)
	var/mob/living/dominated_brain/db = new /mob/living/dominated_brain(src, src, M.name, M)
	db.name = M.name
	db.real_name = M.real_name
	rel_set(db, nameof(db.prey_mind), M.ensure_mind())
	rel_set(db, nameof(db.pred_mind), mind)

	M.languages -= M.temp_languages
	db.languages |= M.languages

	absorb_langs()

	move_player_mind(db.prey_mind, db, "gathered by [src] (dominate prey)", share = TRUE)
	log_admin("[db] ([db.ckey]) has agreed to [src]'s dominate prey attempt, and so no longer occupies their original body.")
	return db

/// The prey's mind leaves this back seat for its own body, binding its
/// identity there again.
/mob/living/dominated_brain/proc/return_to_body()
	move_player_mind(mind, prey_body, "returned to own body from [pred_body]")
	pred_body.absorb_langs()
	to_chat(prey_body, span_warning("Your connection to [pred_body] fades, and you awaken back in your own body!"))
	to_chat(pred_body, span_warning("You feel as though a piece of yourself is missing, as \the [src] returns to their body."))
	log_admin("[prey_body] ([prey_body.ckey]) has returned to their body from [pred_body].")
	dissolved(src)

