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

/datum/task/timed/backup_implanter_backup_implant
	complete_proc = /obj/item/backup_implanter/proc/backup_implant_done
	var/turf/T1

/obj/item/backup_implanter/proc/backup_implant_done(datum/task/timed/backup_implanter_backup_implant/task)
	var/mob/living/M = task.target
	var/mob/living/user = task.actor
	var/turf/T1 = task.T1
	if((get_turf(M) == T1) && LAZYLEN(imps))
		act_message(M, user, others = span_notice("%U% has been backup implanted by %T%."))

		var/obj/item/implant/backup/imp = imps[LAZYLEN(imps)]
		if(imp.handle_implant(M,user.zone_sel.selecting))
			imp.post_implant(M, user)
			own_take_member(src, nameof(imps), imp)
			add_attack_logs(user,M,"Implanted backup implant")

		update()

/obj/item/backup_implanter/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if (!istype(M, /mob/living/carbon))
		return ITEM_INTERACT_FAILURE
	if(user && LAZYLEN(imps))
		act_message(user, M, others = span_notice("%U% is injecting a backup implant into %T%."))

		user.setClickCooldown(DEFAULT_QUICK_COOLDOWN)
		user.do_attack_animation(M)

		var/turf/T1 = get_turf(M)
		if(T1)
			task_start(/datum/task/timed/backup_implanter_backup_implant, user, M, receiver = src, duration = (M == user ? 0 : 5 SECONDS), T1 = T1)
		return ITEM_INTERACT_SUCCESS

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
CAPABILITIES(/obj/structure/backup_implanter_ch)
	op("backup_implanter_ch_interaction_hand", hand(), label("Get implanted"), then(PROC_REF(backup_implanter_ch_interaction_hand)))
	op("backup_implanter_ch_interaction_item", item(/obj/item), then(PROC_REF(backup_implanter_ch_interaction_item)))

/// Old attack_hand (its ..() first was the hand gate).
/obj/structure/backup_implanter_ch/proc/backup_implanter_ch_interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	if(!istype(user, /mob/living/carbon))
		return OP_DECLINE

	if(user)
		act_message(user, null, others = span_notice("%U% is injecting a backup implant into %U%."))

		user.setClickCooldown(DEFAULT_QUICK_COOLDOWN)

		task_timed(user, 2.5 SECONDS, src, src, PROC_REF(self_implant_done), list(user))
	return TRUE

/obj/structure/backup_implanter_ch/proc/self_implant_done(mob/user)
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

/// Old attackby.
/obj/structure/backup_implanter_ch/proc/backup_implanter_ch_interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/O = A.held
	if(O.has_tool_quality(TOOL_WRENCH))

		if(anchored)
			to_chat(user, span_notice("You start to unwrench the implanter."))
			playsound(src, O.usesound, 50, 1)

			task_timed(user, 15 * O.toolspeed, src, src, PROC_REF(wrench_done), list(user, FALSE))
			return OP_PASS

		else
			to_chat(user, span_notice("You start to wrench the implanter into place."))
			playsound(src, O.usesound, 50, 1)

			task_timed(user, 15 * O.toolspeed, src, src, PROC_REF(wrench_done), list(user, TRUE))
			return OP_PASS
	return OP_DECLINE

/obj/structure/backup_implanter_ch/proc/wrench_done(mob/user, anchoring)
	to_chat(user, span_notice(anchoring ? "You wrench the implanter into place." : "You unwrench the implanter."))
	set_anchored(anchoring)

/// LC-refs: the transcore database this uses, looked up by db_key (the databases are a registry).
/obj/item/implant/backup/proc/our_db() as /datum/transcore_db
	return SStranscore.db_by_key(db_key)

