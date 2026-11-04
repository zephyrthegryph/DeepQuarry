// The Casing //
/obj/item/ammo_casing/microbattery
	name = "\'NSCW\' microbattery - UNKNOWN"
	desc = "A miniature battery for an energy weapon."
	icon = 'icons/obj/ammo_vr.dmi'
	icon_state = "nsfw_batt"
	w_class = ITEMSIZE_TINY
	var/shots_left = 4

	leaves_residue = 0
	caliber = "nsfw"
	var/type_color = null
	var/type_name = null
	projectile_type = /obj/item/projectile/beam


CAPABILITIES(/obj/item/ammo_casing/microbattery)
	configure(item_worn(slots = SLOT_BELT | SLOT_EARS))
	configure(item_thrown(force = 1))
	rolls(ROLL_PIXEL, PIXEL_JITTER(10))

/obj/item/ammo_casing/microbattery/look_parts(datum/look/look)

	look.overlay(look_appearance(icon, "[initial(icon_state)]_ends", color = type_color))

/obj/item/ammo_casing/microbattery/expend()
	set_shots_left(shots_left - 1)
