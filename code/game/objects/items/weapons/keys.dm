/obj/item/simple_key
	name = "key"
	desc = "A plain, old-timey key, as one might use to unlock a door."
	icon = 'icons/obj/keys.dmi'
	icon_state = "key_basetype"
	w_class = ITEMSIZE_TINY
	var/keyverb = "uses"				//so simple_keys can be keycards instead, if desired
	var/key_id = "placeholder_DONOTUSE"	//needs to match the associated door's LOCK_ID var

CAPABILITIES(/obj/item/simple_key)
	configure(uses_power(drop = SFX_ITEMS_DROP_RING, pickup = SFX_ITEMS_PICKUP_RING))
