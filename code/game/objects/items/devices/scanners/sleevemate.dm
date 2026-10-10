GLOBAL_DATUM(sleevemate_mob, /mob/living/carbon/human/dummy/mannequin)

//SleeveMate!
/obj/item/sleevemate
	name = "\improper SleeveMate 3700"
	desc = "A hand-held sleeve management tool for performing one-time backups and managing mindstates."
	icon = 'icons/obj/device_alt.dmi'
	icon_state = "sleevemate"
	item_state = "healthanalyzer"
	slot_flags = SLOT_BELT
	throwforce = 3
	w_class = ITEMSIZE_SMALL
	throw_speed = 5
	throw_range = 10
	MATERIAL_BULK(MAT_STEEL, 200)

	/// The stored mind. Its identity (OOC notes and all) is carried with it.
	var/datum/mind/stored_mind
	var/soulcatcher_pref_flags = NONE

	// Resleeving database this machine interacts with. Blank for default database
	// Needs a matching /datum/transcore_db with key defined in code
	var/db_key
	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE

//These don't perform any checks and need to be wrapped by checks
/obj/item/sleevemate/proc/clear_mind()
	rel_clear(src, nameof(stored_mind))

/obj/item/sleevemate/proc/get_mind(mob/living/M)
	ASSERT(M.mind)
	rel_set(src, nameof(stored_mind), M.mind)
	stored_mind().get_identity() // make sure the identity rides the stored mind
	log_game("MIND: [stored_mind().key] ([stored_mind().name]) stored in [src] from [M]")
	soulcatcher_pref_flags = M.soulcatcher_pref_flags
	M.ghostize()
	stored_mind().current = null

/obj/item/sleevemate/proc/put_mind(mob/living/M)
	stored_mind().active = TRUE
	transfer_mind(stored_mind(), M, "sleevemate upload")
	M.soulcatcher_pref_flags = soulcatcher_pref_flags
	clear_mind()



/obj/item/sleevemate/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	// Gather potential subtargets
	var/list/choices = list(M)
	if(istype(M))
		for(var/obj/belly/B as anything in M.vore_organs)
			for(var/mob/living/carbon/human/H in B) // I do want an istype
				choices += H
	// Subtargets
	if(choices.len > 1)
		open_request(src, /datum/prompt/choice/sleevemate_target, PROC_REF(scan_target_chosen), answerer = user, choices = choices, default = M, subject = M, sleevemate = src)
		return ITEM_INTERACT_SUCCESS
	return scan_target(user, M)

/// Picking which of the mobs (the target and the ones in its bellies) to scan. Re-checked on the
/// answer: still next to the target and holding the scanner.
/datum/prompt/choice/sleevemate_target
	title = "Target Validation"
	question = "Ambiguous target. Please validate target:"
	timeout = 0
	ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE
	var/obj/item/sleevemate/sleevemate

CAPABILITIES(/datum/prompt/choice/sleevemate_target)
	ref_one(nameof(sleevemate), /obj/item/sleevemate)

/datum/prompt/choice/sleevemate_target/prepare(datum/act/A)
	..()
	var/obj/item/sleevemate/captured = sleevemate
	rel_clear(src, nameof(sleevemate))
	rel_set(src, nameof(sleevemate), captured)

/datum/prompt/choice/sleevemate_target/recheck_extra()
	return answerer.get_active_hand() == sleevemate ? null : "not holding it"

/obj/item/sleevemate/proc/scan_target_chosen(datum/act/request/A)
	if(!A.answer)
		return
	scan_target(A.request.answerer, A.answer.value)

/obj/item/sleevemate/proc/scan_target(mob/living/user, mob/living/M)
	if(isrobot(M))
		var/mob/living/silicon/robot/R = M
		var/obj/item/dogborg/sleeper/S = locate_in_list(R.module.modules, /obj/item/dogborg/sleeper)
		if(S && S.patient)
			scan_mob(S.patient, user)
			return ITEM_INTERACT_SUCCESS

	if(ishuman(M))
		scan_mob(M, user)
		return ITEM_INTERACT_SUCCESS
	else
		to_chat(user,span_warning("Not a compatible subject to work with!"))
		return ITEM_INTERACT_FAILURE

CAPABILITIES(/obj/item/sleevemate)
	extend(TAG_TOPIC, then(PROC_REF(topic_click_spent), early = TRUE))
	// The timed scans and transfers, started by the topic ops above once they have checked the target.
	op("mindscan_wait", ai(), takes("subject", "nif"), wait(8 SECONDS), on_interrupt(PROC_REF(Topic_timed_failed)), then(PROC_REF(Topic_timed_done)))
	op("bodyscan_wait", ai(), takes("subject"), wait(8 SECONDS), on_interrupt(PROC_REF(Topic_timed_failed)), then(PROC_REF(Topic_timed_done2)))
	op("mindsteal_wait", ai(), takes("subject"), wait(35 SECONDS), then(PROC_REF(Topic_timed_done3)))
	op("mindupload_wait", ai(), takes("subject"), wait(35 SECONDS), then(PROC_REF(Topic_timed_done4)))
	ref_one(nameof(stored_mind), /datum/mind)
	// the old attack_self: what to do with the stored mind
	op("manage_mind", in_hand(), needs(req_bool(PROC_REF(can_manage_mind), because = MSG(sleevemate/empty))),
		asks(/datum/prompt/choice, fields = list("title" = computed(PROC_REF(stored_title)), "question" = "What would you like to do?", "choices" = list("Delete", "Backup", "Cancel"), "buttons" = TRUE, "timeout" = 0)),
		then(PROC_REF(stored_mind_action)))
	emag(list(asks(/datum/prompt/choice, fields = list("question" = computed(PROC_REF(hack_question)), "choices" = list("Body Snatcher", "Mind Binder"), "timeout" = 0)), then(PROC_REF(hack_chosen))), repeatable = TRUE, powered = FALSE)
	op("mindscan", topic("mindscan", arg("target", schema_ref(/mob/living), optional = TRUE, among = TOPIC_IN_MOBS)), then(PROC_REF(topic_mindscan)))
	op("bodyscan", topic("bodyscan", arg("target", schema_ref(/mob/living), optional = TRUE, among = TOPIC_IN_MOBS)), then(PROC_REF(topic_bodyscan)))
	op("mindsteal", topic("mindsteal", arg("target", schema_ref(/mob/living), optional = TRUE, among = TOPIC_IN_MOBS)), asks(/datum/prompt/choice/sleevemate_mindsteal, fields = list("victim" = arg_of("target")), step = "confirm"), then(PROC_REF(topic_mindsteal)))
	op("mindput", topic("mindput", arg("target", schema_ref(/mob/living), optional = TRUE, among = TOPIC_IN_MOBS)), then(PROC_REF(topic_mindput)))
	op("mindupload", topic("mindupload", arg("target", schema_ref(/mob/living), optional = TRUE, among = TOPIC_IN_MOBS)), then(PROC_REF(topic_mindupload)))
	op("mindrelease", topic("mindrelease", arg("target", schema_ref(/mob/living), optional = TRUE, among = TOPIC_IN_MOBS), arg("mindrelease", schema_text(MAX_NAME_LEN), optional = TRUE)), then(PROC_REF(topic_mindrelease)))

/// Requirement: there has to be a stored mind to manage.
/obj/item/sleevemate/proc/can_manage_mind(datum/act/op/A)
	return !!stored_mind

MSG_DEF_SELF(sleevemate/empty, "There is no stored mind in it.")

/obj/item/sleevemate/proc/stored_title(datum/act/A)
	return "Stored: [stored_mind()?.name]"

/// Old attack_self: delete or back up the stored mind.
/obj/item/sleevemate/proc/stored_mind_action(datum/act/op/A)
	var/datum/prompt/R = A.answer
	if(!R || !stored_mind())
		return OP_OK
	var/mob/living/user = A.actor
	switch(R.value)
		if("Delete")
			to_chat(user,span_notice("Internal copy of [stored_mind().name] deleted."))
			clear_mind()
		if("Backup")
			to_chat(user,span_notice("Internal copy of [stored_mind().name] backed up to database."))
			our_db().m_backup(stored_mind(),null,one_time = TRUE)
		if("Cancel")
			return OP_OK
	return OP_OK

/obj/item/sleevemate/proc/scan_mob(mob/living/carbon/human/H, mob/living/user)
	var/output = ""

	output += "<br><br>" + span_boldnotice("[src.name] Scan Results") + "<br>"

	//Mind name
	output += span_bold("Sleeved Mind:") + " "
	if(H.mind)
		output += "[H.mind.name]<br>"
	else
		output += span_warning("Unknown/None") + "<br>"

	//Mind status
	output += span_bold("Mind Status:") + " "
	if(H.client)
		output += "Healthy<br>"
	else
		output += "Space Sleep Disorder<br>"

	//Body status
	output += span_bold("Sleeve Status:") + " "
	if(H.status_flags & FAKEDEATH)
		output += span_warning("Deceased") + "<br>"
	else
		switch(H.stat)
			if(CONSCIOUS)
				output += "Alive<br>"
			if(UNCONSCIOUS)
				output += "Unconscious<br>"
			if(DEAD)
				output += span_warning("Deceased") + "<br>"
			else
				output += span_warning("Unknown") + "<br>"

	//Mind/body comparison
	output += span_bold("Sleeve Pair:")
	if(!H.ckey)
		output += span_warning("No mind in that body") + " [stored_mind() != null ? "\[<a href='byond://?src=\ref[src];target=\ref[H];mindupload=1'>Upload</a>\]" : null]<br>"

	else if(H.mind && (is_changeling(H) || (has_trait(H, UNIQUE_MINDSTRUCTURE) || (ckey(H.mind.key) != H.ckey))))
		output += span_boldwarning("Incorrect mind-sleeve match or hiveminded neurological structure") + "<br>"

	else if(H.mind && ckey(H.mind.key) == H.ckey)
		output += "Appears to be correct mind in body<br>"

	else
		output += "Unable to perform comparison<br>"

	//Actions
	output += "<br><b>-- Possible Actions --</b><br>"
	output += span_bold("Mind-Scan (One Time): ") + "\[<a href='byond://?src=\ref[src];target=\ref[H];mindscan=1'>Perform</a>\]<br>"
	output += span_bold("Body-Scan (One Time): ") + "\[<a href='byond://?src=\ref[src];target=\ref[H];bodyscan=1'>Perform</a>\]<br>"

	//Saving a mind
	output += span_bold("Store Full Mind:") + " "
	if(stored_mind())
		output += span_notice("Already Stored") + " ([stored_mind().name])<br>"
	else if(H.mind)
		output += "\[<a href='byond://?src=\ref[src];target=\ref[H];mindsteal=1'>Perform</a>\]<br>"
	else
		output += span_warning("Unable") + "<br>"

	//Soulcatcher transfer
	if(H.nif)
		var/datum/nifsoft/soulcatcher/SC = H.nif.imp_check(NIF_SOULCATCHER)
		if(SC)
			output += "<br>"
			output += span_bold("Soulcatcher detected ([LAZYLEN(SC.brainmobs)] minds)") + "<br>"
			for(var/mob/living/carbon/brain/caught_soul/mind in SC.brainmobs)
				output += "<i>[mind.name]: </i> [mind.transient == FALSE ? "\[<a href='byond://?src=\ref[src];target=\ref[H];mindrelease=[mind.name]'>Load</a>\]" : span_warning("Incompatible")]<br>"

			if(stored_mind())
				output += span_bold("Store in Soulcatcher: ") + "\[<a href='byond://?src=\ref[src];target=\ref[H];mindput=1'>Perform</a>\]<br>"

	to_chat(user,output)


// Every scan link works only from the active hand.
/obj/item/sleevemate/topic_usable(datum/act/op/A)
	. = ..()
	if(!.)
		return
	return A.actor.get_active_hand() == src

/// Every scan link spends a click, held or not (it was the gate's first act).
/obj/item/sleevemate/proc/topic_click_spent(datum/act/op/A)
	A.actor.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	return OP_OK

/// The link's target, if it is there and next to `user` (says why not otherwise).
/obj/item/sleevemate/proc/topic_target(mob/user, mob/living/target)
	if(!target)
		to_chat(user,span_warning("Unable to operate on that target."))
		return null
	if(!user.Adjacent(target))
		to_chat(user,span_warning("You are too far from that target."))
		return null
	return target

/obj/item/sleevemate/proc/topic_mindscan(datum/act/op/A, href_target)
	var/mob/user = A.actor
	var/mob/living/target = topic_target(user, href_target)
	if(!target)
		return
	if(!target.mind || (target.mind.name in GLOB.prevent_respawns))
		to_chat(user,span_warning("Target seems totally braindead."))
		return

	var/nif
	if(ishuman(target))
		var/mob/living/carbon/human/H = target
		nif = H.nif
		persist_nif_data(H)

	act_message(user, null, MSG_SELF(span_notice("You begin scanning [target]'s mind.")), MSG_OTHERS("%U% begins scanning [target]'s mind."))
	perform_op(user, src, "mindscan_wait", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("subject" = target, "nif" = nif))

/obj/item/sleevemate/proc/topic_bodyscan(datum/act/op/A, href_target)
	var/mob/user = A.actor
	var/mob/living/target = topic_target(user, href_target)
	if(!target)
		return
	if(!ishuman(target))
		to_chat(user,span_warning("Target is not of an acceeptable body type."))
		return

	var/mob/living/carbon/human/H = target

	act_message(user, target, MSG_SELF(span_notice("You begin scanning %T%'s body.")), MSG_OTHERS("%U% begins scanning %T%'s body."))
	perform_op(user, src, "bodyscan_wait", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("subject" = H))

/// The mind steal link, after "Continue": the target is looked at again, as the scan buttons do.
/obj/item/sleevemate/proc/topic_mindsteal(datum/act/op/A, href_target)
	var/mob/living/user = A.actor
	var/mob/living/target = topic_target(user, href_target)
	if(!target)
		return
	if(!target.mind || (target.mind.name in GLOB.prevent_respawns))
		to_chat(user,span_warning("Target seems totally braindead."))
		return
	if(stored_mind())
		to_chat(user,span_warning("There is already someone's mind stored inside"))
		return
	if(A.step_value("confirm") != "Continue")
		return
	act_message(user, null, MSG_SELF(span_notice("You begin downloading [target]'s mind!")), MSG_OTHERS(span_warning("%U% begins downloading [target]'s mind!")))
	perform_op(user, src, "mindsteal_wait", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("subject" = target))

/obj/item/sleevemate/proc/topic_mindput(datum/act/op/A, href_target)
	var/mob/user = A.actor
	var/mob/living/target = topic_target(user, href_target)
	if(!target)
		return
	if(!stored_mind())
		to_chat(user,span_warning("\The [src] no longer has a stored mind."))
		return

	var/mob/living/carbon/human/H = target

	if(!istype(H))
		return //href hacking only

	if(!H.nif)
		return //Lost it? or href hacking

	var/datum/nifsoft/soulcatcher/SC = H.nif.imp_check(NIF_SOULCATCHER)
	if(!SC)
		return //Uninstalled it?

	//Lazzzyyy.
	if(!GLOB.sleevemate_mob)
		GLOB.sleevemate_mob = new()

	if(!(soulcatcher_pref_flags & SOULCATCHER_ALLOW_CAPTURE))
		to_chat(user,span_notice("[GLOB.sleevemate_mob] can't be transferred!"))
		return

	put_mind(GLOB.sleevemate_mob)
	SC.catch_mob(GLOB.sleevemate_mob)
	to_chat(user,span_notice("Mind transferred into Soulcatcher!"))

/obj/item/sleevemate/proc/topic_mindupload(datum/act/op/A, href_target)
	var/mob/user = A.actor
	var/mob/living/target = topic_target(user, href_target)
	if(!target)
		return
	if(!stored_mind())
		to_chat(user,span_warning("\The [src] no longer has a stored mind."))
		return

	if(!istype(target))
		return

	if(ishuman(target))
		var/mob/living/carbon/human/H = target
		if(H.resleeve_lock && stored_mind().loaded_from_ckey != H.resleeve_lock)
			to_chat(user,span_warning("\The [H] is protected from impersonation!"))
			return
		//Changeling bodies. Only changelings can be put in them.
		if(H.changeling_locked && !is_changeling(stored_mind()))
			to_chat(user,span_warning("\The [H] is too complex to put this mind into!"))
			return

	act_message(user, target, MSG_SELF(span_notice("You begin uploading a mind into %T%!")), \
		MSG_OTHERS(span_warning("%U% begins uploading someone's mind into %T%!")))
	perform_op(user, src, "mindupload_wait", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("subject" = target))

/obj/item/sleevemate/proc/topic_mindrelease(datum/act/op/A, href_target, href_mindrelease)
	var/mob/user = A.actor
	var/mob/living/target = topic_target(user, href_target)
	if(!target)
		return
	if(stored_mind())
		to_chat(user,span_warning("There is already someone's mind stored inside"))
		return
	var/mob/living/carbon/human/H = target
	if(!istype(H) || !H.nif)
		return
	var/datum/nifsoft/soulcatcher/SC = H.nif.imp_check(NIF_SOULCATCHER)
	if(!SC)
		return
	for(var/mob/living/carbon/brain/caught_soul/soul in SC.brainmobs)
		if(soul.name == href_mindrelease)
			get_mind(soul)
			rel_remove(SC, nameof(SC.brainmobs), soul)
			to_chat(user,span_notice("Mind downloaded!"))
			return
	to_chat(user,span_notice("Unable to find that mind in Soulcatcher!"))

/obj/item/sleevemate/proc/Topic_timed_done(datum/act/op/A)
	var/mob/living/target = A.arg("subject")
	var/mob/usr_mob = A.actor
	if(QDELETED(target) || !usr_mob.Adjacent(target))
		to_chat(usr_mob,span_warning("You must remain close to your target!"))
		return OP_FAILED
	our_db().m_backup(target.mind,A.arg("nif"),one_time = TRUE)
	to_chat(usr_mob,span_notice("Mind backed up!"))
	return OP_OK

/obj/item/sleevemate/proc/Topic_timed_failed(datum/act/op/A)
	to_chat(A.actor,span_warning("You must remain close to your target!"))

/obj/item/sleevemate/proc/Topic_timed_done2(datum/act/op/A)
	var/mob/living/carbon/human/H = A.arg("subject")
	var/mob/usr_mob = A.actor
	if(QDELETED(H) || !usr_mob.Adjacent(H))
		to_chat(usr_mob,span_warning("You must remain close to your target!"))
		return OP_FAILED
	var/datum/transhuman/body_record/BR = new()
	BR.init_from_mob(H, TRUE, TRUE, database_key = db_key)
	to_chat(usr_mob,span_notice("Body scanned!"))
	return OP_OK

/obj/item/sleevemate/proc/Topic_timed_done3(datum/act/op/A)
	var/mob/living/target = A.arg("subject")
	var/mob/usr_mob = A.actor
	if(QDELETED(target))
		return OP_REFUSED
	if(!stored_mind() && target.mind)
		get_mind(target)
		to_chat(usr_mob,span_notice("Mind downloaded!"))
		return OP_OK
	return OP_FAILED

/obj/item/sleevemate/proc/Topic_timed_done4(datum/act/op/A)
	var/mob/living/target = A.arg("subject")
	var/mob/usr_mob = A.actor
	if(QDELETED(target))
		return OP_REFUSED
	if(!stored_mind())
		to_chat(usr_mob,span_warning("\The [src] no longer has a stored mind."))
		return OP_FAILED
	put_mind(target)
	to_chat(usr_mob,span_notice("Mind transferred into [target]!"))
	return OP_OK

/obj/item/sleevemate/proc/appearance_has_mind()
	return stored_mind() ? TRUE : FALSE

/// The look (the draw sweep: from its template).
/obj/item/sleevemate/draw(datum/look/look)
	..()
	look.state("[initial(icon_state)][appearance_has_mind() ? "_on" : ""]")

/// Pulling a mind out. Re-checked on the answer: the scanner is still in hand and empty, the victim still next to the user.
/datum/prompt/choice/sleevemate_mindsteal
	title = "Confirmation"
	question = "This will remove the target's mind from their body (and from the game as long as they're in the sleevemate). You can put them into a (mindless) body, a NIF, or back them up for normal resleeving, but you should probably have a plan in advance so you don't leave them unable to interact for too long. Continue?"
	choices = list("Continue", "Cancel")
	buttons = TRUE
	timeout = 0
	ask_flags = ASK_HELD | ASK_CAPABLE
	var/mob/living/victim

CAPABILITIES(/datum/prompt/choice/sleevemate_mindsteal)
	ref_one(nameof(victim), /mob/living)

/datum/prompt/choice/sleevemate_mindsteal/prepare(datum/act/A)
	..()
	var/mob/living/captured = victim
	rel_clear(src, nameof(victim))
	rel_set(src, nameof(victim), captured)

/datum/prompt/choice/sleevemate_mindsteal/recheck_extra()
	if(QDELETED(victim))
		return "gone"
	var/obj/item/sleevemate/sleevemate = owner
	if(sleevemate.stored_mind())
		return "already holding a mind"
	if(!answerer.Adjacent(victim))
		return "too far away"
	return null

/obj/item/sleevemate/proc/hack_question(datum/act/A)
	return "How would you like to modify the [src]?"

/// The sequencer's choice: the sleevemate becomes a body snatcher or a mind binder (a card use is spent only when one is picked).
/obj/item/sleevemate/proc/hack_chosen(datum/act/op/A)
	var/datum/prompt/R = A.answer
	var/choice = R?.value
	if(!(choice in list("Body Snatcher","Mind Binder")))
		return OP_DECLINE
	to_chat(A.actor, span_danger("You hack [src]!"))
	// the device is replaced once the emag op has finished with it (the library marks and pays on the holder after this effect)
	after(src, 0, PROC_REF(hacked_into), with = list(choice))
	return OP_OK

/obj/item/sleevemate/proc/hacked_into(choice)
	fx_sparks(src.loc, 5, FALSE)
	play_sfx(src, SFX_SPARKS)
	if(isliving(src.loc))
		var/mob/living/L = src.loc
		L.unEquip(src)
	src.forceMove(get_turf(src))
	if(choice == "Body Snatcher")
		replace_with(src, /obj/item/bodysnatcher)
	if(choice == "Mind Binder")
		replace_with(src, /obj/item/mindbinder)

/// The transcore database this uses, looked up by db_key (the databases are a registry).
/obj/item/sleevemate/proc/our_db() as /datum/transcore_db
	return SStranscore.db_by_key(db_key)

/// Relation view: stored mind (reads null once it is gone).
/obj/item/sleevemate/proc/stored_mind() as /datum/mind
	return stored_mind
