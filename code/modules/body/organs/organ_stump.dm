/obj/item/organ/external/stump
	name = "limb stump"
	icon_name = ""
	dislocated = -1

// ALLOW(init/CTOR_ARGS): internal and limb are constructor arguments from whoever builds it
/obj/item/organ/external/stump/Initialize(mapload, internal, obj/item/organ/external/limb)
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
