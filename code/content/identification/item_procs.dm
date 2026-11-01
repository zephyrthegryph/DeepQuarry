/obj/item/proc/identify(identity_type = IDENTITY_FULL, mob/user)
	if(identity)
		identity.identify(identity_type, user)

/obj/item/proc/is_identified(identity_type = IDENTITY_FULL)
	if(!identity) // No identification datum means nothing to hide.
		return TRUE
	return identity_type & identity.identified
