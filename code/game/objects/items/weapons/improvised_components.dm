/obj/item/material/butterflyconstruction
	name = "unfinished concealed knife"
	desc = "An unfinished concealed knife, it looks like the screws need to be tightened."
	icon = 'icons/obj/buildingobject.dmi'
	icon_state = "butterflystep1"
	force_divisor = 0.1
	thrown_force_divisor = 0.1

/obj/item/material/butterflyconstruction/screwdriver_act(mob/user, obj/item/tool)
	to_chat(user, "You finish the concealed blade weapon.")
	playsound(src, tool.usesound, 50, 1)
	replace_with(src, /obj/item/material/butterfly, material.name)
	return ITEM_INTERACT_SUCCESS

/obj/item/material/butterflyblade
	name = "knife blade"
	desc = "A knife blade. Unusable as a weapon without a grip."
	icon = 'icons/obj/buildingobject.dmi'
	icon_state = "butterfly2"
	force_divisor = 0.1
	thrown_force_divisor = 0.1

/obj/item/material/butterflyhandle
	name = "concealed knife grip"
	desc = "A plasteel grip with screw fittings for a blade."
	icon = 'icons/obj/buildingobject.dmi'
	icon_state = "butterfly1"
	force_divisor = 0.1
	thrown_force_divisor = 0.1

EXTEND_INTERACTIONS(/obj/item/material/butterflyhandle, INTERACT_ITEM(null, PROC_REF(butterflyhandle_interaction_item), REQ_TARGET_STATE(/obj/item/material/butterflyhandle/proc/can_attach_blade)))

/// Both concealed-knife ingredients must be releasable before assembly changes them.
/obj/item/material/butterflyhandle/proc/can_attach_blade(mob/user, atom/target, obj/item/held)
	if(!istype(held, /obj/item/material/butterflyblade))
		return TRUE
	var/reason = loc?.release_refusal(src, user)
	if(reason)
		return reason
	reason = held.loc?.release_refusal(held, user)
	if(reason)
		return reason
	return TRUE

/// Old attackby. It never called ..(): any item stops here (no repair, no storage pickup), but afterattack still follows.
/obj/item/material/butterflyhandle/proc/butterflyhandle_interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(istype(W,/obj/item/material/butterflyblade))
		var/obj/item/material/butterflyblade/B = W
		if(can_attach_blade(user, src, B) != TRUE)
			return INTERACTION_HANDLED_PASS
		if(!loc.release_to(src, user.loc, null, user))
			return INTERACTION_HANDLED_PASS
		if(!B.loc.release_to(B, user.loc, null, user))
			return INTERACTION_HANDLED_PASS
		to_chat(user, "You attach the two concealed blade parts.")
		new /obj/item/material/butterflyconstruction(user.loc, B.material.name)
		consume(W, user)
		consume(src, user)
	return INTERACTION_HANDLED_PASS
