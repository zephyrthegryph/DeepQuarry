/*
 * Plasma Stun
 */
/obj/item/gun/energy/plasmastun
	name = "plasma pulse projector"
	desc = "The RayZar MA21 Selkie is a weapon that uses a laser pulse to ionise the local atmosphere, creating a disorienting pulse of plasma and deafening shockwave as the wave expands."
	icon = 'icons/obj/gun.dmi' // Gun Sprites
	icon_state = "plasma_stun"
	item_state = "plasma_stun"
	fire_delay = 20
	charge_cost = 600
	projectile_type = /obj/item/projectile/energy/plasmastun

CAPABILITIES(/obj/item/gun/energy/plasmastun)
	configure(atom_rules(description_fluff = "RayZar is Ward-Takahashi’s main consumer weapons brand, known for producing and licensing a wide variety of specialist energy weapons of various types and quality primarily for the civilian market. \
	Less well known are RayZar's limited-production experimental projects, often in the form of less-lethal weapon solutions."))
