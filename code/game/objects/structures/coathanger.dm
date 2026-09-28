/obj/structure/coatrack
	name = "coat rack"
	desc = "Rack that holds coats."
	icon = 'icons/obj/coatrack.dmi'
	icon_state = "coatrack0"
	var/coat_handle
	var/list/allowed = list(/obj/item/clothing/suit/storage/toggle/labcoat, /obj/item/clothing/suit/storage/det_trench)

/obj/structure/coatrack/attack_hand(mob/user as mob)
	if(!coat())
		return ..()
	user.visible_message("[user] takes [coat()] off \the [src].", "You take [coat()] off the \the [src]")
	if(!user.put_in_active_hand(coat()))
		coat().loc = get_turf(user)
	coat_handle = null
	update_icon()

/obj/structure/coatrack/attackby(obj/item/W as obj, mob/user as mob)
	var/can_hang = 0
	for (var/T in allowed)
		if(istype(W,T))
			can_hang = 1
	if (can_hang && !coat())
		user.visible_message("[user] hangs [W] on \the [src].", "You hang [W] on the \the [src]")
		coat_handle = om_handle(W)
		user.drop_from_inventory(coat(), src)
		update_icon()
	else
		to_chat(user, span_notice("You cannot hang [W] on [src]"))
		return ..()

/obj/structure/coatrack/CanPass(atom/movable/mover, turf/target)
	var/can_hang = 0
	for (var/T in allowed)
		if(istype(mover,T))
			can_hang = 1

	if (can_hang && !coat())
		src.visible_message("[mover] lands on \the [src].")
		coat_handle = om_handle(mover)
		coat().loc = src
		update_icon()
		return 0
	else
		return 1

/obj/structure/coatrack/update_icon()
	cut_overlays()
	if (istype(coat(), /obj/item/clothing/suit/storage/toggle/labcoat))
		add_overlay("coat_lab")
	if (istype(coat(), /obj/item/clothing/suit/storage/toggle/labcoat/cmo))
		add_overlay("coat_cmo")
	if (istype(coat(), /obj/item/clothing/suit/storage/det_trench))
		add_overlay("coat_det")

/// LC-refs: coat -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/structure/coatrack/proc/coat() as /obj/item/clothing/suit
	return om_resolve(coat_handle)
