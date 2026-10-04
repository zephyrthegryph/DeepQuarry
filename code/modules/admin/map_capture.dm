
ADMIN_VERB(capture_map, R_ADMIN, "Capture Map Part", "Usage: Capture-Map-Part target_x_cord target_y_cord target_z_cord range (captures part of a map originating from bottom left corner).", ADMIN_CATEGORY_SERVER_GAME)

	advance_capture(user)

/datum/admin_verb/capture_map/proc/advance_capture(client/user, stage = 0, pos_type = null, picked_x = null, picked_y = null, picked_z = null, capture_range = null, continue_choice = null)
	var/mob/answerer = user.mob
	if(QDELETED(answerer))
		return
	if(stage <= 0)
		open_request(src, /datum/prompt/choice/admin_map_capture, PROC_REF(capture_question_answered), answerer = answerer, question = "Do you want to use your current loc or a manual number input?", title = "Where?", choices = list("Manual", "Location", "Cancel"), stage = 0)
		return
	if(!pos_type || pos_type == "Cancel")
		return

	var/tx
	var/ty
	var/tz
	if(pos_type == "Location")
		tx = user.mob.x
		ty = user.mob.y
		tz = user.mob.z
	else
		if(stage <= 1)
			open_request(src, /datum/prompt/number/admin_map_capture, PROC_REF(capture_question_answered), answerer = answerer, question = "Select X location", title = "X Loc", max_value = world.maxx, stage = 1, pos_type = pos_type, picked_x = picked_x, picked_y = picked_y, picked_z = picked_z)
			return
		tx = picked_x
		if(stage <= 2)
			open_request(src, /datum/prompt/number/admin_map_capture, PROC_REF(capture_question_answered), answerer = answerer, question = "Select Y location", title = "Y Loc", max_value = world.maxy, stage = 2, pos_type = pos_type, picked_x = picked_x, picked_y = picked_y, picked_z = picked_z)
			return
		ty = picked_y
		if(stage <= 3)
			open_request(src, /datum/prompt/number/admin_map_capture, PROC_REF(capture_question_answered), answerer = answerer, question = "Select Z location", title = "Z Loc", max_value = world.maxz, stage = 3, pos_type = pos_type, picked_x = picked_x, picked_y = picked_y, picked_z = picked_z)
			return
		tz = picked_z

	if(stage <= 4)
		open_request(src, /datum/prompt/number/admin_map_capture, PROC_REF(capture_question_answered), answerer = answerer, question = "Select Range", title = "Range", max_value = 32, stage = 4, pos_type = pos_type, picked_x = picked_x, picked_y = picked_y, picked_z = picked_z)
		return
	var/range = capture_range

	if(isnull(tx) || isnull(ty) || isnull(tz) || isnull(range))
		to_chat(user, span_filter_notice("Capture Map Part, captures part of a map using camara like rendering."))
		to_chat(user, span_filter_notice("Usage: Capture-Map-Part target_x_cord target_y_cord target_z_cord range."))
		to_chat(user, span_filter_notice("Target coordinates specify bottom left corner of the capture, range defines render distance to opposite corner."))
		return

	if(range > 32 || range <= 0)
		to_chat(user, span_filter_notice("Capturing range is incorrect, it must be within 1-32."))
		return

	if(locate(tx,ty,tz))
		var/list/turfstocapture = list()
		var/hasasked = FALSE
		for(var/xoff = 0 to range)
			for(var/yoff = 0 to range)
				var/turf/T = locate(tx + xoff,ty + yoff,tz)
				if(T)
					turfstocapture.Add(T)
				else
					if(!hasasked)
						if(stage <= 5)
							open_request(src, /datum/prompt/choice/admin_map_capture, PROC_REF(capture_question_answered), answerer = answerer, question = "Capture includes non existant turf, Continue capture?", title = "Continue capture?", choices = list("No", "Yes"), stage = 5, pos_type = pos_type, picked_x = picked_x, picked_y = picked_y, picked_z = picked_z, capture_range = capture_range)
							return
						var/answer = continue_choice
						hasasked = TRUE
						if(answer != "Yes")
							return

		var/list/atoms = list()
		for(var/turf/T in turfstocapture)
			atoms.Add(T)
			for(var/atom/A in contents_of(T))
				if(A.invisibility) continue
				atoms.Add(A)

		atoms = sort_atoms_by_layer(atoms)
		var/icon/cap = icon('icons/effects/96x96.dmi', "")
		cap.Scale(range*32, range*32)
		cap.Blend("#000", ICON_OVERLAY)
		for(var/atom/A in atoms)
			if(A)
				var/icon/img = getFlatIcon(A)
				if(istype(img, /icon))
					if(isliving(A))
						var/mob/living/L = A
						if(L.lying)
							img.BecomeLying()
					var/xoff = (A.x - tx) * 32
					var/yoff = (A.y - ty) * 32
					cap.Blend(img, blendMode2iconMode(A.blend_mode),  A.pixel_x + xoff, A.pixel_y + yoff)

		var/file_name = "map_capture_x[tx]_y[ty]_z[tz]_r[range].png"
		to_chat(user, span_filter_notice("Saved capture in cache as [file_name]."))
		DIRECT_OUTPUT(user, browse_rsc(cap, file_name))
	else
		to_chat(user, span_filter_notice("Target coordinates are incorrect."))

/datum/prompt/choice/admin_map_capture
	rights = R_ADMIN
	timeout = 0
	var/stage
	var/pos_type
	var/picked_x
	var/picked_y
	var/picked_z
	buttons = TRUE
	var/capture_range

/datum/prompt/choice/admin_map_capture/begin()
	if(request_recheck(src))
		request_end(src, REQ_CANCELLED, null)
		return
	return ..()

/datum/prompt/number/admin_map_capture
	rights = R_ADMIN
	timeout = 0
	var/stage
	var/pos_type
	var/picked_x
	var/picked_y
	var/picked_z
	default = 1
	min_value = 1
	step = 1

/datum/prompt/number/admin_map_capture/begin()
	if(request_recheck(src))
		request_end(src, REQ_CANCELLED, null)
		return
	return ..()

/datum/prompt/number/admin_map_capture/present(mob/user)
	var/datum/tgui_input_number/prompt/box = new(user, question, title || "Number Input", default, isnull(max_value) ? INFINITY : max_value, isnull(min_value) ? 0 : min_value, timeout, !isnull(step), GLOB.tgui_always_state)
	rel_set(box, nameof(box.prompt), src)
	box.tgui_interact(user)
	return box

/datum/admin_verb/capture_map/proc/capture_question_answered(datum/act/request/A)
	var/datum/result/result = safe_call(PROC_REF(capture_answer), A)
	if(!result.ok)
		stack_trace("om flow capture_map answer capture_answer: [result.error]")

/datum/admin_verb/capture_map/proc/capture_answer(datum/act/request/A)
	if(!A.answer)
		return
	var/client/user = A.request.answerer?.client
	if(!user)
		return
	if(istype(A.request, /datum/prompt/choice/admin_map_capture))
		var/datum/prompt/choice/admin_map_capture/ask = A.request
		if(ask.stage == 0)
			return advance_capture(user, 1, ask.answer_value)
		return advance_capture(user, 6, ask.pos_type, ask.picked_x, ask.picked_y, ask.picked_z, ask.capture_range, ask.answer_value)
	var/datum/prompt/number/admin_map_capture/ask = A.request
	switch(ask.stage)
		if(1)
			return advance_capture(user, 2, ask.pos_type, ask.answer_value)
		if(2)
			return advance_capture(user, 3, ask.pos_type, ask.picked_x, ask.answer_value)
		if(3)
			return advance_capture(user, 4, ask.pos_type, ask.picked_x, ask.picked_y, ask.answer_value)
		if(4)
			return advance_capture(user, 5, ask.pos_type, ask.picked_x, ask.picked_y, ask.picked_z, ask.answer_value)
