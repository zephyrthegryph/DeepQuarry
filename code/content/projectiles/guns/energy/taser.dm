/*
 * Taser
 */
/obj/item/gun/energy/taser
	name = "taser gun"
	desc = "The NT Mk30 NL is a small gun used for non-lethal takedowns. Produced by NT, it's actually a licensed version of a W-T RayZar design."
	icon = 'icons/obj/gun.dmi' // Gun Sprites
	icon_state = "taser"
	item_state = null	//so the human update icon uses the icon_state instead.
	projectile_type = /obj/item/projectile/beam/stun
	charge_cost = 160
	fire_delay = 4

CAPABILITIES(/obj/item/gun/energy/taser)
	configure(atom_rules(description_fluff = "RayZar is Ward-Takahashi’s main consumer weapons brand, known for producing and licensing a wide variety of specialist \
	energy weapons of various types and quality primarily for the civilian market."))

/obj/item/gun/energy/taser/mounted
	name = "mounted taser gun"
	self_recharge = 1
	use_external_power = 1

/obj/item/gun/energy/taser/mounted/augment
	self_recharge = 1
	use_external_power = 0
	use_organic_power = TRUE
	canremove = FALSE

/obj/item/gun/energy/taser/mounted/cyborg
	name = "taser gun"
	recharge_time = 5 // reduced from 7 to 5, Time it takes for shots to recharge (in ticks)

/*
 * Disabler
 */
/obj/item/gun/energy/taser/disabler
	name = "disabler"
	desc = "The NT Mk4 T-DL is a small gun used for non-lethal takedowns. Produced by NT, it's an archaic device which attacks the target's \
	nervous-system and is actually a heavily modified version of the NT Mk30 NL. It's use is heavily regulated due to its effects on the body."
	icon_state = "disabler"
	projectile_type = /obj/item/projectile/beam/stun/disabler
	charge_cost = 480
