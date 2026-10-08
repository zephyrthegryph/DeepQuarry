/obj
	layer = OBJ_LAYER
	plane = OBJ_PLANE
	vis_flags = VIS_INHERIT_PLANE //when this be added to vis_contents of something it inherit something.plane, important for visualisation of obj in openspace.
	unacidable = FALSE //universal "unacidabliness" var, here so you can use it in any obj.
	//Used to store information about the contents of the object.
	var/w_class // Size of the object.
	animate_movement = 2
	var/tmp/in_use = 0 // If we have a user using us, this will be set on. We will check if the user has stopped using us, and thus stop updating and LAGGING EVERYTHING!
	var/show_messages
	var/can_speak = 0 //For MMIs and admin trickery. If an object has a brainmob in its contents, set this to 1 to allow it to speak.

	var/show_examine = TRUE	// Does this pop up on a mob when the mob is examined?

	var/redgate_allowed = TRUE	//can we be taken through the redgate, in either direction?
	var/tmp/being_shocked = FALSE
	var/micro_accepted_scale = 0.5
	var/micro_target = FALSE
	var/explosion_resistance
	/// Department and value attribution used when station-made goods are exported.
	var/economic_department
	var/economic_export_value = 0
	var/economic_producer_account = 0
	/// The finalized department checkout which last sold this physical item.
	/// Prevents one object being presented repeatedly as several distinct sales.
	var/economic_sale_invoice_id = 0

	/// Cached custom fire overlay
	var/tmp/custom_fire_overlay
	/// Particles this obj uses when burning, if any
	var/burning_particles

	var/obj_flags = CAN_BE_HIT

	uses_integrity = TRUE

/obj/proc/set_economic_provenance(department, export_value, producer_account = 0)
	economic_department = department
	economic_export_value = max(1, round(export_value))
	economic_producer_account = producer_account
	emit_contract_event(CONTRACT_EVENT_ITEM_PRODUCED, list(
		"actor_account" = producer_account,
		"department" = department,
		"origin_department" = department,
		"physical_item_id" = REF(src),
		"item_type" = type,
		"item_name" = name,
		"fact_id" = "production:[REF(src)]",
		"fact_revision" = 1,
		"fact_active" = TRUE,
		"metrics" = list("value" = economic_export_value),
		"detail" = "Fabricated [name] for [department].",
	), "item-produced:[REF(src)]", src)
	// Preserve specialized export valuation and never count an object twice.
	make_sellable(/datum/sellable/manufactured)

/// Phase 1 (unbind): an object that blocked air reopens its tile. It is
/// already QDELETED (phase 0), so the recomputed air_block_mask() skips it.
/obj/lifecycle_unbind()
	. = ..()
	if(can_atmos_pass != ATMOS_PASS_YES && isturf(loc))
		update_nearby_tiles()

/obj/on_destroy(force)
	// I really am an idiot why did I make it this way
	if(micro_target)
		for(var/thing in contents_of(src))
			if(!ismob(thing))
				continue
			var/mob/m = thing
			if(isbelly(src.loc))
				m.forceMove(src.loc)
			else
				m.forceMove(get_turf(src.loc))
			act_message(m, src, others = span_notice("%U% tumbles out of %T%!"))

	if(istype(src, /obj/item))
		var/obj/item/I = src
		if(I.possessed_voice && I.possessed_voice.len)
			for(var/mob/living/voice/V in I.possessed_voice)
				if(!V.tf_mob_holder)
					V.ghostize(0)
					V.set_stat(DEAD)
					destroyed(V)

	material_records_teardown(src)
	..()

/// The tgui state an href action on this obj is checked against (topic_usable()).
/obj/proc/topic_state()
	return GLOB.tgui_default_state

// Every href action on an obj needs the user able to interact with it (CanUseTopic()): topic_usable(), a requirement of every topic op (extend(TAG_TOPIC) in CAPABILITIES(/obj), code/datums/behaviours/burning.dm). A type narrows or
// replaces it by overriding topic_usable(); the fingerprint a successful link leaves is an early effect.
/obj/proc/topic_usable(datum/act/op/A)
	var/mob/user = A.actor
	if(!user)
		return FALSE
	return CanUseTopic(user, topic_state()) == STATUS_INTERACTIVE

/// The old gate's name, kept for the two callers in code/game/machinery/syndicatebeacon.dm until the machinery lane converts them.
/obj/proc/topic_allowed(mob/user)
	return user && CanUseTopic(user, topic_state()) == STATUS_INTERACTIVE

/obj/proc/topic_touched(datum/act/op/A)
	CouldUseTopic(A.actor)
	return OP_OK

/obj/op_topic_refused(mob/actor, key, reason, list/href_list)
	..()
	if(reason == /datum/msg/op/topic_gate)
		if(!actor.CanUseObjTopic(src))
			to_chat(actor, span_danger("[icon2html(src, actor.client)]Access Denied!"))
		CouldNotUseTopic(actor)

/obj/proc/CouldUseTopic(mob/user)
	var/atom/host = tgui_host()
	host.add_hiddenprint(user)

/obj/proc/CouldNotUseTopic(mob/user)
	// Nada

/obj/CanUseTopic(mob/user, datum/tgui_state/state = GLOB.tgui_default_state)
	if(user.CanUseObjTopic(src))
		return ..()
	return STATUS_CLOSE

/mob/living/silicon/CanUseObjTopic(obj/O)
	var/id = src.GetIdCard()
	return O.check_access(id)

/mob/proc/CanUseObjTopic()
	return 1

/obj/item/proc/is_used_on(obj/O, mob/user)

/obj/assume_air(datum/gas_mixture/giver)
	if(loc)
		return loc.assume_air(giver)
	else
		return null

/obj/remove_air(amount)
	if(loc)
		return loc.remove_air(amount)
	else
		return null

/obj/return_air()
	if(loc)
		return loc.return_air()
	else
		return null


/obj/proc/hide(h)
	return

/obj/proc/hides_under_flooring()
	return 0

/obj/proc/hear_talk(mob/M, list/message_pieces, verb)
	if(talking_atom)
		talking_atom.catchMessage(multilingual_to_message(message_pieces), M)
/*
	var/mob/mo = locate(/mob) in src
	if(mo)
		var/rendered = span_game(span_say(span_name("[M.name]:") + " " + span_message("[text]"))))
		mo.show_message(rendered, 2)
		*/
	return

/obj/proc/hear_signlang(mob/M as mob, text, verb, datum/language/speaking) // Saycode gets worse every day.
	return FALSE

/obj/proc/see_emote(mob/M as mob, text, emote_type)
	return
// Used to mark a turf as containing objects that are dangerous to step onto.
/obj/proc/register_dangerous_to_step()
	var/turf/T = get_turf(src)
	if(T)
		T.register_dangerous_object(src)

/obj/proc/unregister_dangerous_to_step()
	var/turf/T = get_turf(src)
	if(T)
		T.unregister_dangerous_object(src)

// Test for if stepping on a tile containing this obj is safe to do, used for things like landmines and cliffs.
/obj/proc/is_safe_to_step(mob/living/L)
	return TRUE

/obj/proc/container_resist(mob/living)
	return

// If returns true, pai can interact with the object with a click
/obj/proc/allow_pai_interaction(mob/living/silicon/pai/user, proximity_flag)
	return FALSE

//To be called from things that spill objects on the floor.
//Makes an object move around randomly for a couple of tiles
/obj/proc/tumble(dist = 2)
	if (dist >= 1)
		scatter_steps(dist + rand(0,1))

// Gives the object a shake animation.
/obj/proc/animate_shake()
	var/init_px = pixel_x
	var/shake_dir = pick(-1, 1)
	animate(src, transform=turn(matrix(), 8*shake_dir), pixel_x=init_px + 2*shake_dir, time=1)
	animate(transform=null, pixel_x=init_px, time=6, easing=ELASTIC_EASING)

/obj/item/wash(clean_types)
	. = ..()
	if(blood_overlay && clean_types & CLEAN_WASH)
		overlays.Remove(blood_overlay)
	if(gurgled && clean_types & CLEAN_WASH)
		gurgled = FALSE
		cut_overlay(GLOB.gurgled_overlays[gurgled_color])
	// phoron contamination wash branch removed; .contaminated +
	// GLOB.contamination_overlay are gone (ZAS contamination machinery wasn't
	// ported under LINDA). Restore if contamination gameplay returns.

/obj/vv_get_dropdown()
	. = ..()
	VV_DROPDOWN_OPTION("", "---")
	VV_DROPDOWN_OPTION(VV_HK_MASS_DEL_TYPE, "Delete all of type")
	VV_DROPDOWN_OPTION(VV_HK_FAKE_CONVO, "Add Fake Prop Conversation")


/obj/item/pda/proc/vv_topic_fake_convo(datum/act/op/A)
	var/mob/user = A.actor
	createPropFakeConversation_admin(user)
	return TRUE

/datum/prompt/choice/mass_delete_scope
	choices = list("Strict type","Type and subtypes","Cancel")
	buttons = TRUE
	rights = R_DEBUG|R_SERVER
	timeout = 0

/datum/prompt/choice/mass_delete_scope/prepare(datum/act/A)
	..()
	question = "Strict type ([owner.type]) or type and all subtypes?"

/datum/prompt/yes_no/mass_delete
	rights = R_DEBUG|R_SERVER
	timeout = 0
	var/scope
	/// The second, final confirmation.
	var/second = FALSE

/datum/prompt/yes_no/mass_delete/prepare(datum/act/A)
	..()
	question = second ? "Second confirmation required. Delete?" : "Are you really sure you want to delete all objects of type [owner.type]?"

/// The mass delete questions after the scope are asked unless the scope was "Cancel".
/obj/proc/mass_delete_not_cancelled(datum/act/op/A)
	return A.step_value("scope") != "Cancel"

/// "Delete all of type" (VV): the scope, then two confirmations; this runs when all three are answered.
/obj/proc/vv_topic_mass_delete_type(datum/act/op/A)
	var/mob/user = A.actor
	var/action_type = A.step_value("scope")
	if(action_type == "Cancel")
		return
	var/O_type = type
	switch(action_type)
		if("Strict type")
			var/i = 0
			for(var/obj/Obj in world)
				if(Obj.type == O_type)
					i++
					spent(Obj)
				CHECK_TICK
			if(!i)
				to_chat(user, "No objects of this type exist")
				return
			log_admin("[key_name(user)] deleted all objects of type [O_type] ([i] objects deleted) ")
			message_admins(span_notice("[key_name(user)] deleted all objects of type [O_type] ([i] objects deleted) "))
		if("Type and subtypes")
			var/i = 0
			for(var/obj/Obj in world)
				if(istype(Obj,O_type))
					i++
					spent(Obj)
				CHECK_TICK
			if(!i)
				to_chat(user, "No objects of this type exist")
				return
			log_admin("[key_name(user)] deleted all objects of type or subtype of [O_type] ([i] objects deleted) ")
			message_admins(span_notice("[key_name(user)] deleted all objects of type or subtype of [O_type] ([i] objects deleted) "))

