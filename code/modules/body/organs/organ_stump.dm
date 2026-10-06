/obj/item/organ/external/stump
	name = "limb stump"
	icon_name = ""
	dislocated = -1

CAPABILITIES(/obj/item/organ/external/stump)
	param(nameof(stump_of), pos = 2, keep = FALSE)
	// A stump is the place a limb was on a body: once it has joined one, it lives while it is attached (removed, it ends).
	lives_while(cond_any(cond_not(nameof(stump_joined)), nameof(owner)), watches = list(nameof(owner), nameof(stump_joined)))

/// TRUE once the stump has joined a body.
/obj/item/organ/external/stump/var/stump_joined = FALSE
TRACKED(/obj/item/organ/external/stump, stump_joined)

/obj/item/organ/external/stump/joined_body(mob/living/M)
	. = ..()
	set_stump_joined(TRUE)

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

/obj/item/organ/external/stump/is_usable()
	return 0
