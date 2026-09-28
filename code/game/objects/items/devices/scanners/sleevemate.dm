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
	var/stored_mind_handle
	var/soulcatcher_pref_flags = NONE

	// Resleeving database this machine interacts with. Blank for default database
	// Needs a matching /datum/transcore_db with key defined in code
	var/db_key
	pickup_sound = 'sound/items/pickup/device.ogg'
	drop_sound = 'sound/items/drop/device.ogg'

/obj/item/sleevemate/Initialize(mapload)
	. = ..()

//These don't perform any checks and need to be wrapped by checks
/obj/item/sleevemate/proc/clear_mind()
	stored_mind_handle = null
	update_icon()

/obj/item/sleevemate/proc/get_mind(mob/living/M)
	ASSERT(M.mind)
	stored_mind_handle = om_handle(M.mind)
	stored_mind().get_identity() // make sure the identity rides the stored mind
	log_game("MIND: [stored_mind().key] ([stored_mind().name]) stored in [src] from [M]")
	soulcatcher_pref_flags = M.soulcatcher_pref_flags
	M.ghostize()
	stored_mind().current = null
	update_icon()

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
		om_ask(user, /datum/om/prompt/choice/sleevemate_target, PROC_REF(scan_target_chosen), choices = choices, default = M, subject = M, sleevemate = src)
		return ITEM_INTERACT_SUCCESS
	return scan_target(user, M)

/// Picking which of the mobs (the target and the ones in its bellies) to scan. Re-checked on the
/// answer: still next to the target and holding the scanner.
/datum/om/prompt/choice/sleevemate_target
	title = "Target Validation"
	message = "Ambiguous target. Please validate target:"
	ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE
	var/obj/item/sleevemate/sleevemate

/datum/om/prompt/choice/sleevemate_target/valid()
	return answerer.get_active_hand() == sleevemate ? null : "not holding it"

/obj/item/sleevemate/proc/scan_target_chosen(datum/om/prompt/choice/sleevemate_target/ask)
	scan_target(ask.answerer, ask.choice)

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

DECLARE_INTERACTIONS(/obj/item/sleevemate, INTERACT_USE(null, PROC_REF(interaction_self)))

/obj/item/sleevemate/proc/interaction_self(mob/living/user, obj/item/held, datum/interaction/interaction)
	if(!stored_mind())
		to_chat(user,span_warning("No stored mind in \the [src]."))
		return

	om_ask(user, /datum/om/prompt/choice, PROC_REF(stored_mind_action), title = "Stored: [stored_mind().name]", message = "What would you like to do?", choices = list("Delete","Backup","Cancel"), buttons = TRUE, ask_flags = ASK_HELD | ASK_CAPABLE)

/obj/item/sleevemate/proc/stored_mind_action(datum/om/prompt/choice/ask)
	if(!stored_mind())
		return
	var/mob/living/user = ask.answerer
	switch(ask.choice)
		if("Delete")
			to_chat(user,span_notice("Internal copy of [stored_mind().name] deleted."))
			clear_mind()
		if("Backup")
			to_chat(user,span_notice("Internal copy of [stored_mind().name] backed up to database."))
			our_db().m_backup(stored_mind(),null,one_time = TRUE)
		if("Cancel")
			return

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

	else if(H.mind && (is_changeling(H) || (HAS_TRAIT(H, UNIQUE_MINDSTRUCTURE) || (ckey(H.mind.key) != H.ckey))))
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
			output += span_bold("Soulcatcher detected ([SC.brainmobs.len] minds)") + "<br>"
			for(var/mob/living/carbon/brain/caught_soul/mind in SC.brainmobs)
				output += "<i>[mind.name]: </i> [mind.transient == FALSE ? "\[<a href='byond://?src=\ref[src];target=\ref[H];mindrelease=[mind.name]'>Load</a>\]" : span_warning("Incompatible")]<br>"

			if(stored_mind())
				output += span_bold("Store in Soulcatcher: ") + "\[<a href='byond://?src=\ref[src];target=\ref[H];mindput=1'>Perform</a>\]<br>"

	to_chat(user,output)

/obj/item/sleevemate/Topic(href, href_list)
	usr.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)

	//Sanity checking/href-hacking checking
	if(usr.get_active_hand() != src)
		to_chat(usr,span_warning("You're not holding \the [src]."))
		return

	var/target_ref = href_list["target"]
	var/mob/living/target = locate_in_list(REGISTRY_MEMBERS(REGISTRY_MOBS), target_ref)
	if(!target)
		to_chat(usr,span_warning("Unable to operate on that target."))
		return

	if(!usr.Adjacent(target))
		to_chat(usr,span_warning("You are too far from that target."))
		return

	//The actual options
	if(href_list["mindscan"])
		if(!target.mind || (target.mind.name in GLOB.prevent_respawns))
			to_chat(usr,span_warning("Target seems totally braindead."))
			return

		var/nif
		if(ishuman(target))
			var/mob/living/carbon/human/H = target
			nif = H.nif
			persist_nif_data(H)

		usr.visible_message("[usr] begins scanning [target]'s mind.",span_notice("You begin scanning [target]'s mind."))
		om_task_start(/datum/om/task/timed/sleevemate_topic, usr, target, receiver = src, nif = nif)

		return

	if(href_list["bodyscan"])
		if(!ishuman(target))
			to_chat(usr,span_warning("Target is not of an acceeptable body type."))
			return

		var/mob/living/carbon/human/H = target

		usr.visible_message("[usr] begins scanning [target]'s body.",span_notice("You begin scanning [target]'s body."))
		om_task_start(/datum/om/task/timed/sleevemate_topic2, usr, target, receiver = src, H = H)

		return

	if(href_list["mindsteal"])
		if(!target.mind || (target.mind.name in GLOB.prevent_respawns))
			to_chat(usr,span_warning("Target seems totally braindead."))
			return

		if(stored_mind())
			to_chat(usr,span_warning("There is already someone's mind stored inside"))
			return

		om_ask(usr, /datum/om/prompt/confirm/sleevemate_mindsteal, PROC_REF(mindsteal_confirmed), victim = target)
		return

	if(href_list["mindput"])
		if(!stored_mind())
			to_chat(usr,span_warning("\The [src] no longer has a stored mind."))
			return

		var/mob/living/carbon/human/H = target

		if(!istype(target))
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
			to_chat(usr,span_notice("[GLOB.sleevemate_mob] can't be transferred!"))
			return

		put_mind(GLOB.sleevemate_mob)
		SC.catch_mob(GLOB.sleevemate_mob)
		to_chat(usr,span_notice("Mind transferred into Soulcatcher!"))

	if(href_list["mindupload"])
		if(!stored_mind())
			to_chat(usr,span_warning("\The [src] no longer has a stored mind."))
			return

		if(!istype(target))
			return

		if(ishuman(target))
			var/mob/living/carbon/human/H = target
			if(H.resleeve_lock && stored_mind().loaded_from_ckey != H.resleeve_lock)
				to_chat(usr,span_warning("\The [H] is protected from impersonation!"))
				return
			//Changeling bodies. Only changelings can be put in them.
			if(H.changeling_locked && !is_changeling(stored_mind()))
				to_chat(usr,span_warning("\The [H] is too complex to put this mind into!"))
				return

		usr.visible_message(span_warning("[usr] begins uploading someone's mind into [target]!"),span_notice("You begin uploading a mind into [target]!"))
		om_do_after(usr, 35 SECONDS, target = target, receiver = src, on_done = PROC_REF(Topic_timed_done4), done_args = list(target, usr))

	if(href_list["mindrelease"])
		if(stored_mind())
			to_chat(usr,span_warning("There is already someone's mind stored inside"))
			return
		var/mob/living/carbon/human/H = target
		if(!istype(H) || !H.nif)
			return
		var/datum/nifsoft/soulcatcher/SC = H.nif.imp_check(NIF_SOULCATCHER)
		if(!SC)
			return
		for(var/mob/living/carbon/brain/caught_soul/soul in SC.brainmobs)
			if(soul.name == href_list["mindrelease"])
				get_mind(soul)
				qdel(soul)
				to_chat(usr,span_notice("Mind downloaded!"))
				return
		to_chat(usr,span_notice("Unable to find that mind in Soulcatcher!"))

/datum/om/task/timed/sleevemate_topic
	duration = 8 SECONDS
	complete_proc = /obj/item/sleevemate/proc/Topic_timed_done
	cancel_proc = /obj/item/sleevemate/proc/Topic_timed_failed
	var/nif

/obj/item/sleevemate/proc/Topic_timed_done(datum/om/task/timed/sleevemate_topic/task)
	var/mob/living/target = task.target
	var/nif = task.nif
	var/mob/usr_mob = task.actor
	our_db().m_backup(target.mind,nif,one_time = TRUE)
	to_chat(usr_mob,span_notice("Mind backed up!"))

/obj/item/sleevemate/proc/Topic_timed_failed(datum/om/task/timed/sleevemate_topic/task)
	var/mob/usr_mob = task.actor
	to_chat(usr_mob,span_warning("You must remain close to your target!"))
/datum/om/task/timed/sleevemate_topic2
	duration = 8 SECONDS
	complete_proc = /obj/item/sleevemate/proc/Topic_timed_done2
	cancel_proc = /obj/item/sleevemate/proc/Topic_timed_failed2
	var/mob/living/carbon/human/H

/obj/item/sleevemate/proc/Topic_timed_done2(datum/om/task/timed/sleevemate_topic2/task)
	var/mob/living/carbon/human/H = task.H
	var/mob/usr_mob = task.actor
	var/datum/transhuman/body_record/BR = new()
	BR.init_from_mob(H, TRUE, TRUE, database_key = db_key)
	to_chat(usr_mob,span_notice("Body scanned!"))

/obj/item/sleevemate/proc/Topic_timed_failed2(datum/om/task/timed/sleevemate_topic2/task)
	var/mob/usr_mob = task.actor
	to_chat(usr_mob,span_warning("You must remain close to your target!"))
/obj/item/sleevemate/proc/Topic_timed_done3(mob/living/target, mob/usr_mob)
	if(!stored_mind() && target.mind)
		get_mind(target)
		to_chat(usr_mob,span_notice("Mind downloaded!"))
/obj/item/sleevemate/proc/Topic_timed_done4(mob/living/target, mob/usr_mob)
	if(!stored_mind())
		to_chat(usr_mob,span_warning("\The [src] no longer has a stored mind."))
		return
	put_mind(target)
	to_chat(usr_mob,span_notice("Mind transferred into [target]!"))

/obj/item/sleevemate/update_icon()
	if(stored_mind())
		icon_state = "[initial(icon_state)]_on"
	else
		icon_state = initial(icon_state)

/// Pulling a mind out. Re-checked on the answer: the scanner is still in hand and empty, the victim still next to the user.
/datum/om/prompt/confirm/sleevemate_mindsteal
	title = "Confirmation"
	message = "This will remove the target's mind from their body (and from the game as long as they're in the sleevemate). You can put them into a (mindless) body, a NIF, or back them up for normal resleeving, but you should probably have a plan in advance so you don't leave them unable to interact for too long. Continue?"
	yes_text = "Continue"
	no_text = "Cancel"
	ask_flags = ASK_HELD | ASK_CAPABLE
	var/mob/living/victim

/datum/om/prompt/confirm/sleevemate_mindsteal/valid()
	var/obj/item/sleevemate/sleevemate = subject
	if(sleevemate.stored_mind())
		return "already holding a mind"
	if(!answerer.Adjacent(victim))
		return "too far away"
	return null

/obj/item/sleevemate/proc/mindsteal_confirmed(datum/om/prompt/confirm/sleevemate_mindsteal/ask)
	var/mob/living/user = ask.answerer
	var/mob/living/target = ask.victim
	user.visible_message(span_warning("[user] begins downloading [target]'s mind!"),span_notice("You begin downloading [target]'s mind!"))
	om_do_after(user, 35 SECONDS, target = target, receiver = src, on_done = PROC_REF(Topic_timed_done3), done_args = list(target, user))

/obj/item/sleevemate/emag_act(remaining_charges, mob/user)
	var/list/choices = list("Body Snatcher","Mind Binder")
	om_ask(user, /datum/om/prompt/choice, PROC_REF(hack_chosen), message = "How would you like to modify the [src]?", choices = choices, ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE)
	return 1

/obj/item/sleevemate/proc/hack_chosen(datum/om/prompt/choice/ask)
	var/mob/user = ask.answerer
	var/choice = ask.choice
	if(!(choice in list("Body Snatcher","Mind Binder")))
		return
	to_chat(user,span_danger("You hack [src]!"))
	var/datum/effect/effect/system/spark_spread/spark_system = new /datum/effect/effect/system/spark_spread()
	spark_system.set_up(5, 0, src.loc)
	spark_system.start()
	playsound(src, "sparks", 50, 1)
	if(isliving(src.loc))
		var/mob/living/L = src.loc
		L.unEquip(src)
	src.forceMove(get_turf(src))
	if(choice == "Body Snatcher")
		new /obj/item/bodysnatcher(src.loc)
	if(choice == "Mind Binder")
		new /obj/item/mindbinder(src.loc)
	qdel(src)
	return 1

/// LC-refs: the transcore database this uses, looked up by db_key (the databases are a registry).
/obj/item/sleevemate/proc/our_db() as /datum/transcore_db
	return GLOB.transcore_service.db_by_key(db_key)

/// LC-refs: stored mind -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/item/sleevemate/proc/stored_mind() as /datum/mind
	return om_resolve(stored_mind_handle)
