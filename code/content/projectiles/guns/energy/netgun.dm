//Contains the Energy Net Gun code and information/lore

/obj/item/gun/energy/netgun
	name = "energy net gun"
	desc = "Specially made-to-order by Xenonomix, the  \"Varmint Catcher\" is designed to trap even the most unruly of creatures for safe transport."
	description_fluff = "The Xenonomix Brand XX-1 Energy Net Cannon is a marvel of technology that is used heavily by several departments within NanoTrasen. \
	Whether by scientific departments when capturing specimens on alien worlds to study or by security forces to detain unruly crew, NanoTrasen is deeply \
	appreciative of the \"Varmint Catcher\" Netgun System. WARNING!: Xenonomix and NanoTrasen are not responsible for any injuries caused by the device \
	in any aspect, thank you for understanding."
	icon_state = "netgun"
	item_state = "gun" // Placeholder

	fire_sound = SFX_WEAPONS_ELUGER
	projectile_type = /obj/item/projectile/beam/energy_net
	charge_cost = 800
	fire_delay = 50

/obj/item/gun/energy/netgun/shrink
	name = "compactor energy net gun"
	desc = "A customized version of the famous \"Varmint Catcher\", this \"Varmint Compactor\" is designed to reduce the captured targets to a much more manageable size."
	icon_state = "shrinknetgun"

	projectile_type = /obj/item/projectile/beam/energy_net/shrink

/obj/item/gun/energy/hunter
	name = "Hybrid 'Hunter' net gun"
	desc = "A Hephaestus-designed hybrid of a taser and the energy net gun, usually dubbed 'Hunter' stunner and energy net launcher, \
			for when you want criminals to stop acting like they're on a 20th century British comedy sketch show."
	catalogue_data = list(/datum/category_item/catalogue/information/organization/hephaestus)
	icon_state = "hunter"
	item_state = "gun" // Placeholder
	mode_name = "stun"
	projectile_type = /obj/item/projectile/beam/stun/blue
	charge_cost = 320
	fire_delay = 10


	fire_sound = SFX_WEAPONS_TASER

	firemodes = list(
		list(mode_name="stun", projectile_type=/obj/item/projectile/beam/stun/blue, fire_sound=SFX_WEAPONS_TASER, charge_cost=320, fire_delay=10),
		list(mode_name="capture", projectile_type=/obj/item/projectile/beam/energy_net, fire_sound = SFX_WEAPONS_ELUGER, charge_cost=1200, fire_delay=50)
	)

/// The look: the cell, its charge pips and the fire mode lamp are overlays on the one state.
/obj/item/gun/energy/hunter/draw_charge_state(datum/look/look)
	if(power_supply)
		var/ratio = power_supply.maxcharge > 0 ? power_supply.charge / power_supply.maxcharge : 0
		if(power_supply.charge < charge_cost)
			ratio = 0
		else
			ratio = max(round(ratio, 0.25) * 100, 25)
		look.overlay("[initial(icon_state)]_cell")
		look.overlay("[initial(icon_state)]_[ratio]")
		look.overlay("[initial(icon_state)]_[mode_name]")
