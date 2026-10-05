// The Gun //
/obj/item/gun/projectile/cell_loaded/combat
	name = "cell-loaded revolver"
	desc = "Variety is the spice of life! The Hephaestus 102b 'Nanotech Selectable-Fire Weapon', or NSFW for short, is an unholy hybrid of an ammo-driven  \
	energy weapon that allows the user to mix and match their own fire modes. Up to four combinations of \
	energy beams can be configured at once. Ammo not included."

	description_fluff = "The Hephaestus 'Nanotech Selectable Fire Weapon' allows one to customize their loadout in the field, or before deploying, to achieve various results in a weapon they are already familiar with wielding."
	allowed_magazines = list(/obj/item/ammo_magazine/cell_mag/combat)

/obj/item/gun/projectile/cell_loaded/combat/prototype/get_mechanics_info(list/additional_information)
	return ..(list("Uses interchangeable microbatteries in a magazine. Each battery is a different beam type, and up to three can be loaded in the magazine. \
	Each battery usually provides four discharges of that beam type, and multiple batteries of the same type may be loaded to increase the number of shots for that type.") + additional_information)

/obj/item/gun/projectile/cell_loaded/combat/prototype
	name ="prototype cell-loaded revolver"
	desc = "Variety is the spice of life! A prototype based on Hephaestus 102b 'Nanotech Selectable-Fire Weapon', or NSFW for short, is an unholy hybrid of an ammo-driven  \
	energy weapon that allows the user to mix and match their own fire modes. Up to two combinations of \
	energy beams can be configured at once. Ammo not included."
	description_antag = ""
	allowed_magazines = list(/obj/item/ammo_magazine/cell_mag/combat/prototype)

// The Magazine //
/obj/item/ammo_magazine/cell_mag/combat/get_mechanics_info(list/additional_information)
	return ..(list("This magazine holds NSFW microbatteries to power the NSFW handgun. Up to four can be loaded at once, and each provides four shots of their respective energy type. \
	Loading multiple of the same type will provide additional shots of that type. The batteries can be recharged in a normal recharger.") + additional_information)

/obj/item/ammo_magazine/cell_mag/combat
	name = "microbattery magazine"
	desc = "A microbattery holder for the \'NSFW\'."
	icon_state = "nsfw_mag"
	max_ammo = 4
	x_offset = 4
	ammo_type = /obj/item/ammo_casing/microbattery/combat

/obj/item/ammo_magazine/cell_mag/combat/prototype
	name = "prototype microbattery magazine"
	icon_state = "nsfw_mag_prototype"
	max_ammo = 2
	x_offset = 6
	catalogue_data = null

// The Pack //
/obj/item/storage/secure/briefcase/nsfw_pack
	name = "\improper Hephaestus 102b \'NSFW\' gun kit"
	desc = "A storage case for a multi-purpose handgun. Variety hour!"
	w_class = ITEMSIZE_NORMAL


CAPABILITIES(/obj/item/storage/secure/briefcase/nsfw_pack)
	configure(storage(accepts = list(
		/obj/item/gun/projectile/cell_loaded/combat,
		/obj/item/ammo_magazine/cell_mag/combat,
		/obj/item/ammo_casing/microbattery/combat)))

/obj/item/storage/secure/briefcase/nsfw_pack/Initialize(mapload)
	. = ..()
	new /obj/item/gun/projectile/cell_loaded/combat(src)
	new /obj/item/ammo_magazine/cell_mag/combat(src)
	for(var/path in subtypesof(/obj/item/ammo_casing/microbattery/combat))
		new path(src)

/obj/item/storage/secure/briefcase/nsfw_pack_hos
	starts_with = list(
		/obj/item/gun/projectile/cell_loaded/combat = 1,
		/obj/item/ammo_magazine/cell_mag/combat = 1,
		/obj/item/ammo_casing/microbattery/combat/lethal = 2,
		/obj/item/ammo_casing/microbattery/combat/stun = 3,
		/obj/item/ammo_casing/microbattery/combat/net = 1,
		/obj/item/ammo_casing/microbattery/combat/ion = 1,
	)
	name = "\improper Hephaestus 102b \'NSFW\' gun kit"
	desc = "A storage case for a multi-purpose handgun. Variety hour!"
	w_class = ITEMSIZE_NORMAL


CAPABILITIES(/obj/item/storage/secure/briefcase/nsfw_pack_hos)
	configure(storage(accepts = list(
		/obj/item/gun/projectile/cell_loaded/combat,
		/obj/item/ammo_magazine/cell_mag/combat,
		/obj/item/ammo_casing/microbattery/combat)))

