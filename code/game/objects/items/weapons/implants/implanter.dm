MATERIAL_MIX(/obj/item/implanter, list(MAT_STEEL = 1000, MAT_GLASS = 1000))
/obj/item/implanter
	name = "implanter"
	icon = 'icons/obj/items.dmi'
	icon_state = "implanter0_1"
	item_state = "syringe_0"
	throw_speed = 1
	throw_range = 5
	w_class = ITEMSIZE_SMALL
	var/obj/item/implant/imp = null
	var/active = 1
	///Var for attack_self chain
	var/special_handling = FALSE

CAPABILITIES(/obj/item/implanter)
	op("toggle", in_hand(), label("Toggle"), then(PROC_REF(implanter_self)))
	op("remove_implant", menu(), label("Remove Implant"), needs(carried()), then(PROC_REF(remove_implant_effect)))
	// Implanting the target: at once into yourself, else five seconds while it holds still (it has to be on the tile it was on when the work began).
	op("implant", ai(), takes("patient", "start_turf"), wait(PROC_REF(implant_time), keeps = HELD | TARGET_PRESENT | ALIVE | STAY), then(PROC_REF(implant_done)))

/// Toggle the implanter. Subtypes with special_handling fall through.
/obj/item/implanter/proc/implanter_self(datum/act/op/A)
	var/mob/user = A.actor
	if(special_handling)
		return OP_DECLINE
	active = !active
	to_chat(user, span_notice("You [active ? "" : "de"]activate \the [src]."))
	update()
	return OP_OK

/obj/item/implanter/proc/remove_implant_effect(datum/act/op/A)
	var/mob/user = A.actor
	if(!imp)
		return OP_OK
	if(istype(user, /mob))
		var/mob/M = user
		imp.forceMove(get_turf(src))
		if(M.get_active_hand() == null)
			M.put_in_hands(imp)
		to_chat(M, span_notice("You remove \the [imp] from \the [src]."))
		name = "implanter"
		rel_take(src, nameof(imp))

	update()

	return OP_OK

/obj/item/implanter/proc/update()
	if (src.imp)
		src.icon_state = "implanter1"
	else
		src.icon_state = "implanter0"
	src.icon_state += "_[active]"
	return

/obj/item/implanter/proc/implant_time(datum/act/op/A)
	return A.arg("patient") == A.actor ? 0 : 5 SECONDS

/obj/item/implanter/proc/implant_done(datum/act/op/A)
	var/mob/living/M = A.arg("patient")
	var/mob/living/user = A.actor
	var/turf/T1 = A.arg("start_turf")
	if(!(user && M && (get_turf(M) == T1) && src && src.imp))
		return OP_FAILED
	act_message(user, M, others = span_warning("%T% has been implanted by %U%."))

	add_attack_logs(user,M,"Implanted with [imp.name] using [name]")

	if(imp.handle_implant(M))
		imp.post_implant(M, user)

		if(ishuman(M))
			var/mob/living/carbon/human/H = M
			H.flag_hud_update(IMPLOYAL_HUD)
			H.flag_hud_update(BACKUP_HUD) // Backup HUD updates

	rel_take(src, nameof(imp))
	update()
	return OP_OK

/obj/item/implanter/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if (!istype(M, /mob/living/carbon))
		return ITEM_INTERACT_FAILURE
	if(active)
		if(imp)
			act_message(user, M, others = span_warning("%U% is attempting to implant %T%."))

			user.setClickCooldown(DEFAULT_QUICK_COOLDOWN)
			user.do_attack_animation(M)

			var/turf/T1 = get_turf(M)
			if(T1)
				perform_op(user, src, "implant", src, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("patient" = M, "start_turf" = T1))
				return ITEM_INTERACT_SUCCESS
	else
		to_chat(user, span_warning("You need to activate \the [src.name] first."))
	return ITEM_INTERACT_FAILURE

/obj/item/implanter/loyalty
	name = "implanter-loyalty"

/obj/item/implanter/loyalty/ownership()
	. = ..()
	. += owns(nameof(imp), policy = OWN_CONTAINED, starts = /obj/item/implant/loyalty)

/obj/item/implanter/loyalty
	icon_state = "implanter1_1" // loaded: what update() would show

/obj/item/implanter/explosive
	name = "implanter (E)"

/obj/item/implanter/explosive/ownership()
	. = ..()
	. += owns(nameof(imp), policy = OWN_CONTAINED, starts = /obj/item/implant/explosive)

/obj/item/implanter/explosive
	icon_state = "implanter1_1" // loaded: what update() would show

/obj/item/implanter/adrenalin
	name = "implanter-adrenalin"

/obj/item/implanter/adrenalin/ownership()
	. = ..()
	. += owns(nameof(imp), policy = OWN_CONTAINED, starts = /obj/item/implant/adrenalin)

/obj/item/implanter/adrenalin
	icon_state = "implanter1_1" // loaded: what update() would show

/obj/item/implanter/compressed
	name = "implanter (C)"
	icon_state = "cimplanter1"

/obj/item/implanter/compressed/ownership()
	. = ..()
	. += owns(nameof(imp), policy = OWN_CONTAINED, starts = /obj/item/implant/compressed)

/obj/item/implanter/compressed
	icon_state = "implanter1_1" // loaded: what update() would show

/obj/item/implanter/compressed/update()
	if (imp)
		var/obj/item/implant/compressed/c = imp
		if(!c.scanned())
			icon_state = "cimplanter1"
		else
			icon_state = "cimplanter2"
	else
		icon_state = "cimplanter0"
	return

/obj/item/implanter/compressed/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	var/obj/item/implant/compressed/c = imp
	if(!c)
		return ITEM_INTERACT_FAILURE
	if(c.scanned() == null)
		to_chat(user, "Please scan an object with the implanter first.")
		return ITEM_INTERACT_FAILURE
	..()

/obj/item/implanter/compressed/afterattack(atom/A, mob/user as mob, proximity)
	if(!proximity)
		return
	if(!active)
		to_chat(user, span_warning("Activate \the [src.name] first."))
		return
	if(istype(A,/obj/item) && imp)
		var/obj/item/implant/compressed/c = imp
		if (c.scanned())
			to_chat(user, span_warning("Something is already scanned inside the implant!"))
			return
		rel_set(c, nameof(c.scanned), A)
		if(istype(A, /obj/item/storage))
			to_chat(user, span_warning("You can't store \the [A.name] in this!"))
			rel_clear(c, nameof(c.scanned))
			return
		if(ishuman(A.loc))
			var/mob/living/carbon/human/H = A.loc
			H.remove_from_mob(A)
		else if(istype(A.loc,/obj/item/storage))
			var/obj/item/storage/S = A.loc
			S.remove_from_storage(A)
		var/obj/item/scanned_item = A
		scanned_item.moveToNullspace()
		update()

/obj/item/implanter/restrainingbolt
	name = "implanter (bolt)"

/obj/item/implanter/restrainingbolt/ownership()
	. = ..()
	. += owns(nameof(imp), policy = OWN_CONTAINED, starts = /obj/item/implant/restrainingbolt)

/obj/item/implanter/restrainingbolt
	icon_state = "implanter1_1" // loaded: what update() would show


// universal translator implant.

/obj/item/implanter/vrlanguage
	name = "implanter-language"

/obj/item/implanter/vrlanguage/ownership()
	. = ..()
	. += owns(nameof(imp), policy = OWN_CONTAINED, starts = /obj/item/implant/vrlanguage)

/obj/item/implanter/vrlanguage
	icon_state = "implanter1_1" // loaded: what update() would show

/obj/item/implanter/ownership()
	. = ..()
	. += owns(nameof(imp), policy = OWN_CONTAINED)
