/obj/item/Initialize(mapload)
	if(init_hide_identity)
		rel_set(src, nameof(identity), new identity_type(src))
	return ..()


/obj/item/proc/hide_identity() // Mostly for admins to make things secret.
	if(!identity)
		rel_set(src, nameof(identity), new identity_type(src))
	else
		identity.unidentify()

/obj/item/proc/identify(identity_type = IDENTITY_FULL, mob/user)
	if(identity)
		identity.identify(identity_type, user)

/obj/item/proc/is_identified(identity_type = IDENTITY_FULL)
	if(!identity) // No identification datum means nothing to hide.
		return TRUE
	return identity_type & identity.identified
