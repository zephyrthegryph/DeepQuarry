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

DECLARE_INTERACTIONS(/obj/item/implanter, INTERACT_SELF("Toggle", PROC_REF(implanter_self)))

/// Old attack_self: toggle the implanter. Subtypes with special_handling fall through.
/obj/item/implanter/proc/implanter_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(special_handling)
		return FALSE
	active = !active
	to_chat(user, span_notice("You [active ? "" : "de"]activate \the [src]."))
	update()
	return TRUE

/obj/item/implanter/proc/remove_implant_effect(mob/user, obj/item/held, datum/interaction/interaction)

	if(!imp)
		return
	if(istype(user, /mob))
		var/mob/M = user
		imp.forceMove(get_turf(src))
		if(M.get_active_hand() == null)
			M.put_in_hands(imp)
		to_chat(M, span_notice("You remove \the [imp] from \the [src]."))
		name = "implanter"
		own_take(src, "imp")

	update()

	return

/obj/item/implanter/proc/update()
	if (src.imp)
		src.icon_state = "implanter1"
	else
		src.icon_state = "implanter0"
	src.icon_state += "_[active]"
	return

/// Implanting the target: at once into yourself, else five seconds while it holds still.
/datum/om/task/timed/implant
	complete_proc = /obj/item/implanter/proc/implant_done
	var/turf/start_turf

/obj/item/implanter/proc/implant_done(datum/om/task/timed/implant/task)
	var/mob/living/M = task.target
	var/mob/living/user = task.actor
	var/turf/T1 = task.start_turf
	if(!(user && M && (get_turf(M) == T1) && src && src.imp))
		return
	M.visible_message(span_warning("[M] has been implanted by [user]."))

	add_attack_logs(user,M,"Implanted with [imp.name] using [name]")

	if(imp.handle_implant(M))
		imp.post_implant(M)

		if(ishuman(M))
			var/mob/living/carbon/human/H = M
			BITSET(H.hud_updateflag, IMPLOYAL_HUD)
			BITSET(H.hud_updateflag, BACKUP_HUD) // Backup HUD updates

	own_take(src, "imp")
	update()

/obj/item/implanter/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if (!istype(M, /mob/living/carbon))
		return ITEM_INTERACT_FAILURE
	if(active)
		if(imp)
			M.visible_message(span_warning("[user] is attempting to implant [M]."))

			user.setClickCooldown(DEFAULT_QUICK_COOLDOWN)
			user.do_attack_animation(M)

			var/turf/T1 = get_turf(M)
			if(T1)
				om_task_start(/datum/om/task/timed/implant, user, M, duration = (M == user ? 0 : 5 SECONDS), receiver = src, start_turf = T1)
				return ITEM_INTERACT_SUCCESS
	else
		to_chat(user, span_warning("You need to activate \the [src.name] first."))
	return ITEM_INTERACT_FAILURE

/obj/item/implanter/loyalty
	name = "implanter-loyalty"

DECLARE_DEFAULT_CHILD(/obj/item/implanter/loyalty, "imp", /obj/item/implant/loyalty)
/obj/item/implanter/loyalty
	icon_state = "implanter1_1" // loaded: what update() would show

/obj/item/implanter/explosive
	name = "implanter (E)"

DECLARE_DEFAULT_CHILD(/obj/item/implanter/explosive, "imp", /obj/item/implant/explosive)
/obj/item/implanter/explosive
	icon_state = "implanter1_1" // loaded: what update() would show

/obj/item/implanter/adrenalin
	name = "implanter-adrenalin"

DECLARE_DEFAULT_CHILD(/obj/item/implanter/adrenalin, "imp", /obj/item/implant/adrenalin)
/obj/item/implanter/adrenalin
	icon_state = "implanter1_1" // loaded: what update() would show

/obj/item/implanter/compressed
	name = "implanter (C)"
	icon_state = "cimplanter1"

DECLARE_DEFAULT_CHILD(/obj/item/implanter/compressed, "imp", /obj/item/implant/compressed)
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
		rel_set(c, "scanned", A)
		if(istype(A, /obj/item/storage))
			to_chat(user, span_warning("You can't store \the [A.name] in this!"))
			rel_clear(c, "scanned")
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

DECLARE_DEFAULT_CHILD(/obj/item/implanter/restrainingbolt, "imp", /obj/item/implant/restrainingbolt)
/obj/item/implanter/restrainingbolt
	icon_state = "implanter1_1" // loaded: what update() would show


// universal translator implant.

/obj/item/implanter/vrlanguage
	name = "implanter-language"

DECLARE_DEFAULT_CHILD(/obj/item/implanter/vrlanguage, "imp", /obj/item/implant/vrlanguage)
/obj/item/implanter/vrlanguage
	icon_state = "implanter1_1" // loaded: what update() would show

OWN(/obj/item/implanter, imp, OWN_CONTAINED)

/// Old object verbs.
EXTEND_INTERACTIONS(/obj/item/implanter, \
	INTERACT_VERB("Remove Implant", PROC_REF(remove_implant_effect), REQ_IN_INVENTORY), \
)
