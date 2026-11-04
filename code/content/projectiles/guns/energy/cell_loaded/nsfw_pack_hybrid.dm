// The Pack //
/obj/item/storage/secure/briefcase/nsfw_pack_hybrid
	starts_with = list(
		/obj/item/gun/projectile/cell_loaded = 1,
		/obj/item/ammo_magazine/cell_mag/advanced = 1,
		/obj/item/ammo_casing/microbattery/combat/stun = 3,
		/obj/item/ammo_casing/microbattery/combat/net = 2,
		/obj/item/ammo_casing/microbattery/medical/brute3 = 1,
		/obj/item/ammo_casing/microbattery/medical/burn3 = 1,
		/obj/item/ammo_casing/microbattery/medical/stabilize2 = 1,
		/obj/item/ammo_casing/microbattery/medical/toxin3 = 1,
		/obj/item/ammo_casing/microbattery/medical/omni3 = 1,
	)
	name = "hybrid cell-loaded gun kit"
	desc = "A storage case for a multi-purpose handgun. Variety hour!"
	w_class = ITEMSIZE_NORMAL


CAPABILITIES(/obj/item/storage/secure/briefcase/nsfw_pack_hybrid)
	configure(storage(accepts = list(
		/obj/item/gun/projectile/cell_loaded,
		/obj/item/ammo_magazine/cell_mag,
		/obj/item/ammo_casing/microbattery)))
