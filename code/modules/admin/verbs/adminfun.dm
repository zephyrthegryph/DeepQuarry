ADMIN_VERB(admin_explosion, R_ADMIN|R_FUN, "Explosion", ADMIN_VERB_NO_DESCRIPTION, ADMIN_CATEGORY_HIDDEN, atom/orignator as obj|mob|turf)
	var/devastation = verb_ask(user, "a1", args, /datum/om/prompt/number, message = "Range of total devastation. -1 to none", title = "Input", min = -1)
	if(isnull(devastation))
		return
	if(devastation == null)
		return
	var/heavy = verb_ask(user, "a2", args, /datum/om/prompt/number, message = "Range of heavy impact. -1 to none", title = "Input", min = -1)
	if(isnull(heavy))
		return
	if(heavy == null)
		return
	var/light = verb_ask(user, "a3", args, /datum/om/prompt/number, message = "Range of light impact. -1 to none", title = "Input", min = -1)
	if(isnull(light))
		return
	if(light == null)
		return
	var/flash = verb_ask(user, "a4", args, /datum/om/prompt/number, message = "Range of flash. -1 to none", title = "Input", min = -1)
	if(isnull(flash))
		return
	if(flash == null)
		return

	if ((devastation != -1) || (heavy != -1) || (light != -1) || (flash != -1))
		if ((devastation > 20) || (heavy > 20) || (light > 20))
			var/_answer_a5 = verb_ask(user, "a5", args, /datum/om/prompt/choice/alert, message = "Are you sure you want to do this? It will laaag.", title = "Confirmation", choices = list("Yes", "No"))
			if(isnull(_answer_a5))
				return
			if (_answer_a5 != "Yes")
				return

		explosion(orignator, devastation, heavy, light, flash)
		log_admin("[key_name(user)] created an explosion ([devastation],[heavy],[light],[flash]) at ([orignator.x],[orignator.y],[orignator.z])")
		message_admins("[key_name_admin(user)] created an explosion ([devastation],[heavy],[light],[flash]) at ([orignator.x],[orignator.y],[orignator.z])", 1)
		feedback_add_details("admin_verb","EXPL") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(admin_emp, R_ADMIN|R_FUN, "EM Pulse", ADMIN_VERB_NO_DESCRIPTION, ADMIN_CATEGORY_HIDDEN, atom/orignator as obj|mob|turf)
	var/mob/answerer = user.mob
	if(QDELETED(answerer))
		return
	var/datum/admin_emp_review/review = new
	rel_set(review, nameof(review.actor), answerer)
	rel_set(review, nameof(review.originator), orignator)
	review.originator_expected = !isnull(orignator)
	review.client_ckey = user.ckey
	review.ask_next()

ADMIN_VERB(gib_them, (R_ADMIN|R_FUN), "Gib", ADMIN_VERB_NO_DESCRIPTION, ADMIN_CATEGORY_HIDDEN, mob/victim in REGISTRY_MEMBERS(REGISTRY_MOBS))
	var/mob/answerer = user.mob
	if(QDELETED(answerer))
		return
	open_request(src, /datum/prompt/choice/admin_gib_target, PROC_REF(gib_confirmed), answerer = answerer, victim = victim, victim_expected = !isnull(victim))

/datum/admin_verb/gib_them/proc/gib_confirmed(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/result/result = safe_call(PROC_REF(apply_gib), context)
	if(!result.ok)
		stack_trace("om flow gib_them answer gib_confirmed: [result.error]")

/datum/admin_verb/gib_them/proc/apply_gib(datum/act/request/context)
	var/client/user = context.request.answerer.client
	var/confirm = context.request.answer_value
	var/datum/prompt/choice/admin_gib_target/request = context.request
	var/mob/victim = request.victim
	if(confirm != "Yes")
		return
	//Due to the delay here its easy for something to have happened to the mob
	if(!victim)
		return

	log_admin("[key_name(user)] has gibbed [key_name(victim)]")
	message_admins("[key_name_admin(user)] has gibbed [key_name_admin(victim)]", 1)

	if(isobserver(victim))
		gibs(victim.loc)
		return

	victim.gib()
	feedback_add_details("admin_verb","GIB") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

ADMIN_VERB(gib_self, R_HOLDER, "Gibself", "Give yourself the same treatment you give others.", ADMIN_CATEGORY_FUN_DO_NOT)
	var/mob/answerer = user.mob
	if(QDELETED(answerer))
		return
	open_request(src, /datum/prompt/choice/admin_gib_self, PROC_REF(gib_confirmed), answerer = answerer)

/datum/admin_verb/gib_self/proc/gib_confirmed(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/result/result = safe_call(PROC_REF(apply_gib), context)
	if(!result.ok)
		stack_trace("om flow gib_self answer gib_confirmed: [result.error]")

/datum/admin_verb/gib_self/proc/apply_gib(datum/act/request/context)
	var/client/user = context.request.answerer.client
	var/confirm = context.request.answer_value
	if(!confirm)
		return
	if(confirm == "Yes")
		if (isobserver(user.mob)) // so they don't spam gibs everywhere
			return
		else
			user.mob.gib()

		log_admin("[key_name(user)] used gibself.")
		message_admins(span_blue("[key_name_admin(user)] used gibself."), 1)
		feedback_add_details("admin_verb","GIBS") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

/datum/prompt/choice/admin_gib_target
	rights = R_ADMIN|R_FUN
	timeout = 0
	question = "You sure?"
	title = "Confirm"
	choices = list("Yes", "No")
	buttons = TRUE
	var/mob/victim
	var/victim_expected = FALSE

CAPABILITIES(/datum/prompt/choice/admin_gib_target)
	ref_one(nameof(victim), /mob)

/datum/prompt/choice/admin_gib_target/prepare(datum/act/context)
	. = ..()
	var/mob/captured = victim
	rel_clear(src, nameof(victim))
	rel_set(src, nameof(victim), captured)

/datum/prompt/choice/admin_gib_target/recheck_extra()
	. = ..()
	if(.)
		return
	return victim_expected && QDELETED(victim) ? "target is gone" : null

/datum/prompt/choice/admin_gib_target/begin()
	if(request_recheck(src))
		request_end(src, REQ_CANCELLED, null)
		return
	return ..()

/datum/prompt/choice/admin_gib_self
	rights = R_HOLDER
	timeout = 0
	question = "You sure?"
	title = "Confirm"
	choices = list("Yes", "No")
	buttons = TRUE

/datum/prompt/choice/admin_gib_self/begin()
	if(request_recheck(src))
		request_end(src, REQ_CANCELLED, null)
		return
	return ..()

/datum/admin_emp_review
	var/mob/actor
	var/atom/originator
	var/originator_expected = FALSE
	var/client_ckey
	var/stage = 1
	var/heavy
	var/med
	var/light
	var/long

CAPABILITIES(/datum/admin_emp_review)
	ref_one(nameof(actor), /mob)
	ref_one(nameof(originator), /atom)

/datum/admin_emp_review/proc/refusal()
	if(QDELETED(actor) || !GLOB.directory[client_ckey])
		return "participant is gone"
	return originator_expected && QDELETED(originator) ? "target is gone" : null

/datum/admin_emp_review/proc/retire()
	qdel(src) // ALLOW(lifecycle): Finished nonspatial request state has no inventory release contract.

/datum/admin_emp_review/proc/ask_next()
	var/client/user = GLOB.directory[client_ckey]
	rel_set(src, nameof(actor), user.mob)
	var/question
	switch(stage)
		if(1)
			question = "Range of heavy pulse."
		if(2)
			question = "Range of medium pulse."
		if(3)
			question = "Range of light pulse."
		if(4)
			question = "Range of long pulse."
	open_request(src, /datum/prompt/number/admin_emp_range, PROC_REF(range_answered), answerer = actor, question = question)

/datum/admin_emp_review/proc/range_answered(datum/act/request/context)
	var/datum/result/result = safe_call(PROC_REF(continue_range), context)
	if(!result.ok)
		stack_trace("om flow admin_emp answer continue_range: [result.error]")
		retire()

/datum/admin_emp_review/proc/continue_range(datum/act/request/context)
	if(!context.answer)
		retire()
		return
	switch(stage)
		if(1)
			heavy = context.request.answer_value
		if(2)
			med = context.request.answer_value
		if(3)
			light = context.request.answer_value
		if(4)
			long = context.request.answer_value
	stage++
	if(stage <= 4)
		ask_next()
		return
	apply_pulse()
	retire()

/datum/admin_emp_review/proc/apply_pulse()
	var/client/user = GLOB.directory[client_ckey]
	var/atom/orignator = originator
	if (heavy || med || light || long)
		empulse(orignator, heavy, med, light, long)
		log_admin("[key_name(user)] created an EM Pulse ([heavy],[med],[light],[long]) at ([orignator.x],[orignator.y],[orignator.z])")
		message_admins("[key_name_admin(user)] created an EM PUlse ([heavy],[med],[light],[long]) at ([orignator.x],[orignator.y],[orignator.z])", 1)
		feedback_add_details("admin_verb","EMP") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

/datum/prompt/number/admin_emp_range
	rights = R_ADMIN|R_FUN
	timeout = 0
	title = "Input"
	default = 0
	min_value = 0
	step = 1

/datum/prompt/number/admin_emp_range/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/admin_emp_review/review = owner
	return review.refusal()

/datum/prompt/number/admin_emp_range/begin()
	if(request_recheck(src))
		request_end(src, REQ_CANCELLED, null)
		return
	return ..()

/datum/prompt/number/admin_emp_range/present(mob/user)
	var/datum/tgui_input_number/prompt/box = new(user, question, title || "Number Input", default, isnull(max_value) ? INFINITY : max_value, isnull(min_value) ? 0 : min_value, timeout, !isnull(step), GLOB.tgui_always_state)
	rel_set(box, nameof(box.prompt), src)
	box.tgui_interact(user)
	return box
