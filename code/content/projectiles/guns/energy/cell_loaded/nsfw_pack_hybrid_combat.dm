/obj/item/storage/secure/briefcase/nsfw_pack_hybrid_combat
	starts_with = list(
		/obj/item/gun/projectile/cell_loaded = 1,
		/obj/item/ammo_magazine/cell_mag/advanced = 1,
		/obj/item/ammo_casing/microbattery/combat/shotstun = 2,
		/obj/item/ammo_casing/microbattery/combat/lethal = 3,
		/obj/item/ammo_casing/microbattery/combat/ion = 1,
		/obj/item/ammo_casing/microbattery/combat/xray = 1,
		/obj/item/ammo_casing/microbattery/medical/stabilize2 = 1,
		/obj/item/ammo_casing/microbattery/medical/haste = 1,
		/obj/item/ammo_casing/microbattery/medical/resist = 1,
	)
	name = "military cell-loaded gun kit"
	desc = "A storage case for a multi-purpose handgun. Variety hour!"
	w_class = ITEMSIZE_NORMAL


CAPABILITIES(/obj/item/storage/secure/briefcase/nsfw_pack_hybrid_combat)
	configure(storage(accepts = list(
		/obj/item/gun/projectile/cell_loaded,
		/obj/item/ammo_magazine/cell_mag,
		/obj/item/ammo_casing/microbattery)))
