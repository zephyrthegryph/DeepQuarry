// The Gun //
/obj/item/gun/projectile/cell_loaded/medical/get_mechanics_info(list/additional_information)
	return ..(list("Uses interchangeable nanite discharge cells in a magazine. Each cell is a different healing beam type, and up to three can be loaded in the magazine. \
	Each cell usually provides four discharges of that beam type, and multiple cells of the same type may be loaded to increase the number of shots for that type.") + additional_information)

/obj/item/gun/projectile/cell_loaded/medical
	name = "cell-loaded medigun"
	desc = "The Nanite Emergency Response Device 'medigun', or NERD for short, is a powerful cell-based ranged healing device based on the HI-102b NSCW. \
	It uses an internal nanite fabricator, powered and controlled by discrete cells, to deliver a variety of effects at range. Up to six combinations of \
	healing beams can be configured at once, depending on cartridge used. Ammo not included."
	catalogue_data = list(/datum/category_item/catalogue/information/organization/vey_med)

	icon_state = "nerd"
	description_fluff = "The Vey-Med NERD 'Medigun' allows one to customize their loadout in the field, or before deploying, to allow emergency response personnel to deliver a variety of ranged healing options."
	description_antag = ""
	allowed_magazines = list(/obj/item/ammo_magazine/cell_mag/medical)

/obj/item/gun/projectile/cell_loaded/medical/cmo
	name = "advanced cell-loaded medigun"
	desc = "This is a variation on the NERD 'Medigun', a powerful cell-based ranged healing device based on the HI-102b NSCW. \
	It has an extended sight for increased accuracy, and much more comfortable grip. Ammo not included."

	icon_state = "nerd_cmo"



/obj/item/ammo_magazine/cell_mag/medical/get_mechanics_info(list/additional_information)
	return ..(list("This magazine holds self-charging nanite fabricators to power the NERD 'Medigun'. Up to three can be loaded at once, and each provides four shots of their respective healing type. \
	Loading multiple of the same type will provide additional shots of that type. The batteries can be recharged in a normal recharger.") + additional_information)

/obj/item/ammo_magazine/cell_mag/medical //medical
	name = "nanite magazine"
	desc = "A nanite fabrication magazine for the \'NERD\'"
	catalogue_data = list(/datum/category_item/catalogue/information/organization/vey_med)
	ammo_type = /obj/item/ammo_casing/microbattery/medical
	icon_state = "nerd_mag"

/obj/item/ammo_magazine/cell_mag/medical/advanced
	name = "advanced nanite magazine"
	desc = "A nanite discharge cell for the \'NERD\'. This one is a more advanced version which can hold six individual nanite discharge cells."
	max_ammo = 6
	x_offset = 3
	icon_state = "nerd_mag_extended"


// The Pack //
/obj/item/storage/secure/briefcase/nerd_pack_med
	starts_with = list(
		/obj/item/gun/projectile/cell_loaded/medical = 1,
		/obj/item/ammo_magazine/cell_mag/medical = 1,
		/obj/item/ammo_casing/microbattery/medical/brute = 1,
		/obj/item/ammo_casing/microbattery/medical/burn = 1,
		/obj/item/ammo_casing/microbattery/medical/stabilize = 1,
	)
	name = "\improper NERD \'Medigun\' kit"
	desc = "A storage case for a multi-purpose healing gun. Variety hour!"
	icon_state = "medbriefcase"
	w_class = ITEMSIZE_NORMAL


CAPABILITIES(/obj/item/storage/secure/briefcase/nerd_pack_med)
	configure(storage(accepts = list(
		/obj/item/gun/projectile/cell_loaded/medical,
		/obj/item/ammo_magazine/cell_mag/medical,
		/obj/item/ammo_casing/microbattery/medical)))

/obj/item/storage/secure/briefcase/nerd_pack_cmo
	starts_with = list(
		/obj/item/gun/projectile/cell_loaded/medical/cmo = 1,
		/obj/item/ammo_magazine/cell_mag/medical = 1,
		/obj/item/ammo_casing/microbattery/medical/brute = 1,
		/obj/item/ammo_casing/microbattery/medical/burn = 1,
		/obj/item/ammo_casing/microbattery/medical/stabilize = 1,
		/obj/item/ammo_casing/microbattery/medical/toxin = 1,
		/obj/item/ammo_casing/microbattery/medical/omni = 1,
	)
	name = "\improper Advanced NERD \'Medigun\' kit"
	desc = "A storage case for a multi-purpose healing gun. Variety hour!"
	icon_state = "medbriefcase"
	w_class = ITEMSIZE_NORMAL


CAPABILITIES(/obj/item/storage/secure/briefcase/nerd_pack_cmo)
	configure(storage(accepts = list(
		/obj/item/gun/projectile/cell_loaded/medical,
		/obj/item/ammo_magazine/cell_mag/medical,
		/obj/item/ammo_casing/microbattery/medical)))

