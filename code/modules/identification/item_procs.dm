/obj/item/Initialize(mapload)
	if(init_hide_identity)
		identity = new identity_type(src)
	return ..()

/obj/item/Destroy()
	if(identity)
		QDEL_NULL(identity)
	return ..()

/proc/hide_identity(obj/item/source) // Mostly for admins to make things secret.
	if(!source.identity)
		source.identity = new source.identity_type(source)
	else
		source.identity.unidentify()

/obj/item/proc/identify(identity_type = IDENTITY_FULL, mob/user)
	if(identity)
		identity.identify(identity_type, user)

/proc/is_identified(obj/item/source, identity_type = IDENTITY_FULL)
	if(!source.identity) // No identification datum means nothing to hide.
		return TRUE
	return identity_type & source.identity.identified
