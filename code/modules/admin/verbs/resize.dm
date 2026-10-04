ADMIN_VERB_ONLY_CONTEXT_MENU(resize, (R_ADMIN|R_FUN|R_VAREDIT), "Resize", mob/living/living_target)
	user.do_resize(living_target)

ADMIN_VERB(mob_resize, (R_ADMIN|R_FUN|R_VAREDIT), "Resize Mob", "Resizes any living mob without any restrictions on size.", ADMIN_CATEGORY_FUN_EVENT_KIT)
	var/mob/answerer = user.mob
	if(QDELETED(answerer))
		return
	open_request(src, /datum/prompt/choice/admin_resize_target, PROC_REF(resize_target_selected), answerer = answerer, choices = REGISTRY_MEMBERS(REGISTRY_MOBS))

/datum/admin_verb/mob_resize/proc/resize_target_selected(datum/act/request/A)
	if(!A.answer)
		return
	open_target_resize(A)

/datum/admin_verb/mob_resize/proc/open_target_resize(datum/act/request/A)
	var/mob/target_mob = A.request.answer_value
	var/client/user = A.request.answerer.client
	user.do_resize(target_mob)

/client/proc/do_resize(mob/living/living_target, size_multiplier = null, answered = FALSE)
	if(!answered)
		var/mob/answerer = mob
		if(QDELETED(answerer))
			return
		var/datum/admin_resize_review/review = new
		rel_set(review, nameof(review.actor), answerer)
		rel_set(review, nameof(review.target), living_target)
		review.target_expected = !isnull(living_target)
		review.client_ckey = ckey
		open_request(review, /datum/prompt/number/admin_resize_amount, TYPE_PROC_REF(/datum/admin_resize_review, answered), answerer = answerer)
		return
	if(isnull(size_multiplier))
		return
	if(!size_multiplier)
		return //cancelled

	size_multiplier = clamp(size_multiplier, -50, 50)   //being able to make people upside down is fun. Also 1000 is way, WAY too big. Honestly 50 is too big but at least you can see 50 and it doesn't break the rendering.
	var/can_be_big = living_target.has_large_resize_bounds()
	var/very_big = is_extreme_size(size_multiplier)

	if(very_big && can_be_big) // made an extreme size in an area that allows it, don't assume adminbuse
		to_chat(src, span_warning("[living_target] will lose this size upon moving into an area where this size is not allowed."))
	else if(very_big) // made an extreme size in an area that doesn't allow it, assume adminbuse
		to_chat(src, span_warning("[living_target] will retain this normally unallowed size outside this area."))

	living_target.resize(size_multiplier, animate = TRUE, uncapped = TRUE, ignore_prefs = TRUE)

	log_and_message_admins("has changed [key_name(living_target)]'s size multiplier to [size_multiplier].", src)
	feedback_add_details("admin_verb","RESIZE")

/datum/prompt/choice/admin_resize_target
	rights = R_ADMIN|R_FUN|R_VAREDIT
	timeout = 0
	question = "Select target to resize."
	title = "Resize Target"
	recheck_on_open = TRUE

/datum/prompt/choice/admin_resize_target/recheck_extra()
	. = ..()
	if(.)
		return
	if(!isnull(answer_value))
		var/mob/picked = answer_value
		return QDELETED(picked) ? "target is gone" : null

/datum/admin_resize_review
	var/mob/actor
	var/mob/target
	var/target_expected = FALSE
	var/client_ckey

CAPABILITIES(/datum/admin_resize_review)
	ref_one(nameof(actor), /mob)
	ref_one(nameof(target), /mob)

/datum/admin_resize_review/proc/refusal()
	if(QDELETED(actor) || !GLOB.directory[client_ckey])
		return "participant is gone"
	return target_expected && QDELETED(target) ? "target is gone" : null

/datum/admin_resize_review/proc/retire()
	qdel(src) // ALLOW(lifecycle): Finished nonspatial request state has no inventory release contract.

/datum/admin_resize_review/proc/answered(datum/act/request/A)
	finish(A)
	retire()

/datum/admin_resize_review/proc/finish(datum/act/request/A)
	if(!A.answer)
		return
	var/client/user = GLOB.directory[client_ckey]
	user.do_resize(target, A.request.answer_value, TRUE)

/datum/prompt/number/admin_resize_amount
	rights = R_ADMIN|R_FUN|R_VAREDIT
	timeout = 0
	question = "Input size multiplier."
	title = "Resize"
	default = 1
	min_value = 0
	max_value = INFINITY
	step = null
	recheck_on_open = TRUE

/datum/prompt/number/admin_resize_amount/recheck_extra()
	. = ..()
	if(.)
		return
	var/datum/admin_resize_review/review = owner
	return review.refusal()

/datum/prompt/number/admin_resize_amount/present(mob/user)
	var/datum/tgui_input_number/prompt/box = new(user, question, title || "Number Input", default, isnull(max_value) ? INFINITY : max_value, isnull(min_value) ? 0 : min_value, timeout, !isnull(step), GLOB.tgui_always_state)
	rel_set(box, nameof(box.prompt), src)
	box.tgui_interact(user)
	return box
