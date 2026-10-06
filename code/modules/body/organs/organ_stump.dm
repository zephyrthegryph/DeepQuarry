/obj/item/organ/external/stump
	name = "limb stump"
	icon_name = ""
	dislocated = -1

CAPABILITIES(/obj/item/organ/external/stump)
	param(nameof(stump_of), pos = 2, keep = FALSE)

/// The limb the stump replaces (its constructor param, dropped after init).
/obj/item/organ/external/stump/var/tmp/obj/item/organ/external/stump_of

// ALLOW(init/INSTANCE_STATE): a stump takes the place, joint and damage of the limb it replaces, robotic when both are
/obj/item/organ/external/stump/Initialize(mapload, internal)
	var/obj/item/organ/external/limb = stump_of
	if(istype(limb))
		organ_tag = limb.organ_tag
		body_part = limb.body_part
		amputation_point = limb.amputation_point
		joint = limb.joint
		parent_organ = limb.parent_organ
	. = ..(mapload, internal)
	if(istype(limb))
		set_max_damage(limb.max_damage)
		if((limb.is_robotic()) && (!parent || (parent.is_robotic())))
			robotize() //if both limb and the parent are robotic, the stump is robotic too

/obj/item/organ/external/stump/is_stump()
	return 1

/obj/item/organ/external/stump/removed()
	..()
	spent(src)

/obj/item/organ/external/stump/is_usable()
	return 0
