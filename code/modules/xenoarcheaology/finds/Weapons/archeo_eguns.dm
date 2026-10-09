//snowflake guns for xenoarch because you can't override the update_icon() proc inside the giant mess that is find creation
/obj/item/gun/energy/laser/xenoarch
	name = "Relic Rifle"
	desc = "An anomalous rifle that shoots abnormal types of beams."
	icon = 'icons/obj/xenoarchaeology.dmi'
	one_handed_penalty = FALSE

/// The relic is given its sprite when found; the charge meter never draws over it.
/obj/item/gun/energy/laser/xenoarch/draw_charge_state(datum/look/look)
	return


/obj/item/gun/energy/laser/xenoarch
	icon = 'icons/obj/xenoarchaeology.dmi'

/obj/item/gun/energy/laser/practice/xenoarch
	icon = 'icons/obj/xenoarchaeology.dmi'

/obj/item/gun/energy/xray/xenoarch
	icon = 'icons/obj/xenoarchaeology.dmi'

/obj/item/gun/energy/captain/xenoarch
	icon = 'icons/obj/xenoarchaeology.dmi'
