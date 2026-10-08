////////////////////////////////
//// Resleeving implant
//// for both organic and synthetic crew
////////////////////////////////

//The backup implant itself
/obj/item/implant/backup
	name = "backup implant"
	desc = "A mindstate backup implant that occasionally stores a copy of one's mind on a central server for backup purposes."
	catalogue_data = list(/datum/category_item/catalogue/technology/resleeving)
	icon = 'icons/vore/custom_items_vr.dmi'
	icon_state = "backup_implant"
	known_implant = TRUE

	// Resleeving database this machine interacts with. Blank for default database
	// Needs a matching /datum/transcore_db with key defined in code
	var/db_key

/obj/item/implant/backup/get_data()
	var/dat = {"
<b>Implant Specifications:</b><BR>
<b>Name:</b> [using_map.company_name] Employee Backup Implant<BR>
<b>Life:</b> ~8 hours.<BR>
<b>Important Notes:</b> Implant is life-limited due to licensing restrictions. Dissolves into harmless biomaterial after around ~8 hours, the typical work shift.<BR>
<HR>
<b>Implant Details:</b><BR>
<b>Function:</b> Contains a small swarm of nanobots that perform neuron scanning to create mind-backups.<BR>
<b>Special Features:</b> Will allow restoring of backups during the 8-hour period it is active.<BR>
<b>Integrity:</b> Generally very survivable. Susceptible to being destroyed by acid."}
	return dat

CAPABILITIES(/obj/item/implant/backup)
	param(nameof(db_key), pos = 1)

/obj/item/implant/backup/post_implant(mob/living/carbon/human/H)
	if(istype(H))
		H.flag_hud_update(BACKUP_HUD)
		rel_add(our_db(), nameof(/datum/transcore_db::implants), src)

		return 1

MATERIAL_MIX(/obj/item/backup_implanter, list(MAT_STEEL = 2000, MAT_GLASS = 2000))
//New, modern implanter instead of old style implanter.
/obj/item/backup_implanter
	name = "backup implanter"
	desc = "After discovering that Nanotrasen was just re-using the same implanters over and over again on organics, leading to cross-contamination, Vey-Medical designed this self-cleaning model. Holds four backup implants at a time."
	catalogue_data = list(/datum/category_item/catalogue/technology/resleeving)
	icon = 'icons/obj/device_alt.dmi'
	icon_state = "bimplant"
	item_state = "syringe_0"
	throw_speed = 1
	throw_range = 5
	w_class = ITEMSIZE_SMALL
	var/list/obj/item/implant/backup/imps // the implanter's loaded implants (owned, lazy)
	var/max_implants = 4 //Iconstates need to exist due to the update proc!

	var/db_key // To give to the baby implants

CAPABILITIES(/obj/item/backup_implanter)
	owns_many(nameof(imps), /obj/item/implant/backup)
	op("backup_implanter_interaction_eject", in_hand(), label("Eject implant"), then(PROC_REF(backup_implanter_interaction_eject)))
	op("backup_implanter_interaction_load", item(/obj/item/implant/backup), label("Load implant"), then(PROC_REF(backup_implanter_interaction_load)))
	op("implant", at_target(/mob/living/carbon), when(PROC_REF(implanter_loaded)), priority(OP_PRIORITY_PART), answers(INTENT_USE, INTENT_ATTACK), label("Implant"),
		needs(req_adjacent()), begins(MSG(backup_implanter/implanting)), starts(PROC_REF(implanter_swing)), wait(PROC_REF(implant_time)), then(PROC_REF(backup_implant_done)))

/obj/item/backup_implanter/Initialize(mapload)
	. = ..()
	for(var/i = 1 to max_implants)
		var/obj/item/implant/backup/imp = new(src, db_key)
		rel_add(src, nameof(imps), imp)
		imp.germ_level = 0
	update()

/obj/item/backup_implanter/proc/update()
	icon_state = "[initial(icon_state)][LAZYLEN(imps)]"
	germ_level = 0

/// Old attack_self.
/obj/item/backup_implanter/proc/backup_implanter_interaction_eject(datum/act/op/A)
	var/mob/user = A.actor
	if(!istype(user))
		return

	if(LAZYLEN(imps))
		to_chat(user, span_notice("You eject a backup implant."))
		var/obj/item/implant/backup/imp = imps[LAZYLEN(imps)]
		imp.forceMove(get_turf(user))
		own_take_member(src, nameof(imps), imp)
		user.put_in_any_hand_if_possible(imp)
		update()
	else
		to_chat(user, span_warning("\The [src] is empty."))

	return

/// Old attackby.
/obj/item/backup_implanter/proc/backup_implanter_interaction_load(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(LAZYLEN(imps) < max_implants)
		if(!move_into(src, nameof(src.imps), W, user))
			return OP_PASS
		W.germ_level = 0
		update()
		to_chat(user, span_notice("You load \the [W] into \the [src]."))
	else
		to_chat(user, span_warning("\The [src] is already full!"))
	return OP_PASS

MSG_DEF(backup_implanter/implanting, null, "%U% is injecting a backup implant into %T%.")

/// The op's `when()`: a loaded implanter used on a carbon (an empty one is an ordinary hit).
/obj/item/backup_implanter/proc/implanter_loaded(datum/act/op/A)
	return LAZYLEN(imps) > 0

/// Five seconds on someone else, at once on yourself.
/obj/item/backup_implanter/proc/implant_time(datum/act/op/A)
	return A.target == A.actor ? 0 : 5 SECONDS

/// The swing: the click cooldown and the attack animation of the legacy attack.
/obj/item/backup_implanter/proc/implanter_swing(datum/act/op/A)
	var/mob/living/user = A.actor
	user.setClickCooldown(DEFAULT_QUICK_COOLDOWN)
	user.do_attack_animation(A.target)

/obj/item/backup_implanter/proc/backup_implant_done(datum/act/op/A)
	var/mob/living/M = A.target
	var/mob/living/user = A.actor
	if(!LAZYLEN(imps))
		return OP_FAILED
	if(M == user)
		implanter_swing(A) // no wait to start it in: the swing is made as it goes in
	act_message(M, user, others = span_notice("%U% has been backup implanted by %T%."))

	var/obj/item/implant/backup/imp = imps[LAZYLEN(imps)]
	if(imp.handle_implant(M,user.zone_sel.selecting))
		imp.post_implant(M, user)
		own_take_member(src, nameof(imps), imp)
		add_attack_logs(user,M,"Implanted backup implant")

	update()
	return OP_OK

//The glass case for the implant
/obj/item/implantcase/backup
	name = "glass case - 'backup'"
	desc = "A case containing a backup implant."
	icon_state = "implantcase-b"

/obj/item/implantcase/backup/ownership()
	. = ..()
	. += owns(nameof(imp), policy = OWN_CONTAINED, starts = /obj/item/implant/backup)

//The box of backup implants
/obj/item/storage/box/backup_kit
	name = "backup implant kit"
	desc = "Box of stuff used to implant backup implants."
	icon_state = "implant"
	item_state_slots = list(slot_r_hand_str = "syringe_kit", slot_l_hand_str = "syringe_kit")

/obj/item/storage/box/backup_kit
	starts_with = list(
		/obj/item/implantcase/backup = 7,
		/obj/item/implanter = 1,
	)

/*
/obj/item/implant/backup/full
	name = "backup implant"
	desc = "A normal wireless cortical stack with neutrino and QE transmission for constant-stream consciousness upload."
*/

//Infinite use implanter. Feel free to make proper sprites for it or whatnot.
//I guess this would make more sense as a machine but there's all that extra machine code it doesn't need.
/obj/structure/backup_implanter_ch
	name = "\improper Backup implanter"
	icon = 'icons/obj/computer3.dmi'
	icon_state = "laptop-gun"
	desc = "After discovering clients constantly lacked staff to replace implants, Vey-Medical designed this version capable of creating implants on demand."
	anchored = TRUE
	germ_level = 0

//Click to get implant.
MSG_DEF(backup_implanter/injecting, null, "%U% is injecting a backup implant into %U%.")
MSG_DEF_SELF(backup_implanter/unwrenching, span_notice("You start to unwrench the implanter."))
MSG_DEF_SELF(backup_implanter/wrenching, span_notice("You start to wrench the implanter into place."))
MSG_DEF_SELF(backup_implanter/unwrenched, span_notice("You unwrench the implanter."))
MSG_DEF_SELF(backup_implanter/wrenched, span_notice("You wrench the implanter into place."))

CAPABILITIES(/obj/structure/backup_implanter_ch)
	op("self_implant", hand(), label("Get implanted"), when(req_actor_kind(/mob/living/carbon)), begins(MSG(backup_implanter/injecting)), wait(2.5 SECONDS), then(PROC_REF(self_implant_done)))
	op("unwrench", tool(TOOL_WRENCH), when(nameof(anchored)), begins(MSG(backup_implanter/unwrenching)), wait(1.5 SECONDS), then(PROC_REF(unwrench_done)), says(MSG(backup_implanter/unwrenched)))
	op("wrench", tool(TOOL_WRENCH), when(cond_not(nameof(anchored))), begins(MSG(backup_implanter/wrenching)), wait(1.5 SECONDS), then(PROC_REF(wrench_done)), says(MSG(backup_implanter/wrenched)))

/obj/structure/backup_implanter_ch/proc/self_implant_done(datum/act/op/A)
	var/mob/user = A.actor
	//Create the actual implant.
	var/obj/item/implant/backup/imp = new(src.contents)
	imp.germ_level = 0

	//Implant the implant.
	if(imp.handle_implant(user, user.zone_sel.selecting))
		imp.post_implant(user, user)
		add_attack_logs(user, user, "Implanted backup implant")
		act_message(user, null, others = span_notice("%U% has been backup implanted by %U%."))

	//If implanting somehow fails, delete the implant.
	else
		spent(imp, user)

/obj/structure/backup_implanter_ch/proc/unwrench_done(datum/act/op/A)
	playsound(src, A.held?.usesound, 50, 1)
	set_anchored(FALSE)

/obj/structure/backup_implanter_ch/proc/wrench_done(datum/act/op/A)
	playsound(src, A.held?.usesound, 50, 1)
	set_anchored(TRUE)

/// LC-refs: the transcore database this uses, looked up by db_key (the databases are a registry).
/obj/item/implant/backup/proc/our_db() as /datum/transcore_db
	return SStranscore.db_by_key(db_key)

