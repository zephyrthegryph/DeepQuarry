/obj/item/material/butterflyconstruction
	name = "unfinished concealed knife"
	desc = "An unfinished concealed knife, it looks like the screws need to be tightened."
	icon = 'icons/obj/buildingobject.dmi'
	icon_state = "butterflystep1"
	force_divisor = 0.1
	thrown_force_divisor = 0.1

CAPABILITIES(/obj/item/material/butterflyconstruction)
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), wait(0), then(PROC_REF(screwdriver_used)))

/obj/item/material/butterflyconstruction/proc/screwdriver_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	to_chat(user, "You finish the concealed blade weapon.")
	playsound(src, tool.usesound, 50, 1)
	replace_with(src, /obj/item/material/butterfly, material.name)
	return OP_OK

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

/// Both concealed-knife ingredients must be releasable before assembly changes them: null, or why not.
/obj/item/material/butterflyhandle/proc/attach_refusal(mob/user, obj/item/held)
	var/reason = loc?.release_refusal(src, user)
	if(reason)
		return reason
	return held.loc?.release_refusal(held, user)

CAPABILITIES(/obj/item/material/butterflyhandle)
	op("handle_item", item(/obj/item), priority(OP_PRIORITY_PART + 1), then(PROC_REF(butterflyhandle_interaction_item)))

/// Old attackby: a blade goes on the grip. It never called ..(): any item stops here (no repair, no storage pickup), but afterattack still follows.
/obj/item/material/butterflyhandle/proc/butterflyhandle_interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(istype(W,/obj/item/material/butterflyblade))
		var/obj/item/material/butterflyblade/B = W
		var/why = attach_refusal(user, B)
		if(why)
			to_chat(user, span_warning(capitalize("[why].")))
			return OP_PASS
		if(!loc.release_to(src, user.loc, null, user))
			return OP_PASS
		if(!B.loc.release_to(B, user.loc, null, user))
			return OP_PASS
		to_chat(user, "You attach the two concealed blade parts.")
		new /obj/item/material/butterflyconstruction(user.loc, B.material.name)
		consume(W, user)
		consume(src, user)
	return OP_PASS
