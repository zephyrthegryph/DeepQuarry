// Searchable loot tables (loot_search(), code/datums/loot/loot.dm). Each declaration is complete:
// it carries every tier and setting it had, inherited ones included.

// Subtype for mecha and mecha accessories. These might not always be on the surface.
DECLARE_LOOT(/loot/mecha, \
	LOOT_TABLE(\
		/obj/random/tool = 4, \
		/obj/item/stack/cable_coil/random = 1, \
		/obj/random/tank = 1, \
		/obj/random/tech_supply/component = 3, \
		/obj/effect/decal/remains/lizard = 1, \
		/obj/effect/decal/remains/mouse = 1, \
		/obj/effect/decal/remains/robot = 1, \
		LOOT_STACK(1, /obj/item/stack/material/steel, 40)), \
	LOOT_UNCOMMON(20, \
		/obj/item/mecha_parts/mecha_equipment/weapon/energy/taser, \
		/obj/item/mecha_parts/mecha_equipment/weapon/energy/riggedlaser, \
		/obj/item/mecha_parts/mecha_equipment/tool/hydraulic_clamp, \
		/obj/item/mecha_parts/mecha_equipment/tool/drill, \
		/obj/item/mecha_parts/mecha_equipment/generator), \
	LOOT_RARE(10, \
		/obj/item/mecha_parts/mecha_equipment/weapon/energy/laser, \
		/obj/item/mecha_parts/mecha_equipment/generator/nuclear, \
		/obj/item/mecha_parts/mecha_equipment/tool/jetpack), \
	LOOT_DEPLETION(9, FALSE))

// Stuff you may find attached to a ripley.
DECLARE_LOOT(/loot/mecha/ripley, \
	LOOT_TABLE(\
		/obj/random/tool, \
		/obj/item/stack/cable_coil/random, \
		/obj/random/tank, \
		/obj/random/tech_supply/component, \
		LOOT_STACK(1, /obj/item/stack/material/steel, 25), \
		LOOT_STACK(1, /obj/item/stack/material/glass, 10), \
		LOOT_STACK(1, /obj/item/stack/material/plasteel, 5), \
		/obj/item/mecha_parts/chassis/ripley, \
		/obj/item/mecha_parts/part/ripley_torso, \
		/obj/item/mecha_parts/part/ripley_left_arm, \
		/obj/item/mecha_parts/part/ripley_right_arm, \
		/obj/item/mecha_parts/part/ripley_left_leg, \
		/obj/item/mecha_parts/part/ripley_right_leg, \
		/obj/item/kit/paint/ripley, \
		/obj/item/kit/paint/ripley/flames_red, \
		/obj/item/kit/paint/ripley/flames_blue), \
	LOOT_UNCOMMON(20, \
		/obj/item/mecha_parts/mecha_equipment/tool/hydraulic_clamp, \
		/obj/item/mecha_parts/mecha_equipment/tool/drill/diamonddrill, \
		/obj/item/mecha_parts/mecha_equipment/antiproj_armor_booster, \
		/obj/item/mecha_parts/mecha_equipment/tool/extinguisher), \
	LOOT_RARE(10, \
		/obj/item/mecha_parts/mecha_equipment/gravcatapult, \
		/obj/item/mecha_parts/mecha_equipment/tool/rcd, \
		/obj/item/mecha_parts/mecha_equipment/weapon/energy/flamer/rigged), \
	LOOT_DEPLETION(9, FALSE))

// Death-Ripley, same common, but more combat-exosuit-based
DECLARE_LOOT(/loot/mecha/deathripley, \
	LOOT_TABLE(\
		/obj/random/tool, \
		/obj/item/stack/cable_coil/random, \
		/obj/random/tank, \
		/obj/random/tech_supply/component, \
		LOOT_STACK(1, /obj/item/stack/material/steel, 40), \
		LOOT_STACK(1, /obj/item/stack/material/glass, 20), \
		LOOT_STACK(1, /obj/item/stack/material/plasteel, 10), \
		/obj/item/mecha_parts/chassis/ripley, \
		/obj/item/mecha_parts/part/ripley_torso, \
		/obj/item/mecha_parts/part/ripley_left_arm, \
		/obj/item/mecha_parts/part/ripley_right_arm, \
		/obj/item/mecha_parts/part/ripley_left_leg, \
		/obj/item/mecha_parts/part/ripley_right_leg, \
		/obj/item/kit/paint/ripley/death), \
	LOOT_UNCOMMON(20, \
		/obj/item/mecha_parts/mecha_equipment/tool/hydraulic_clamp/safety, \
		/obj/item/mecha_parts/mecha_equipment/weapon/energy/riggedlaser, \
		/obj/item/mecha_parts/mecha_equipment/repair_droid, \
		/obj/item/mecha_parts/mecha_equipment/tesla_energy_relay), \
	LOOT_RARE(10, \
		/obj/item/mecha_parts/mecha_equipment/tool/rcd, \
		/obj/item/mecha_parts/mecha_equipment/wormhole_generator, \
		/obj/item/mecha_parts/mecha_equipment/weapon/energy/flamer/rigged), \
	LOOT_DEPLETION(9, FALSE))

// Medimech loot
DECLARE_LOOT(/loot/mecha/odysseus, \
	LOOT_TABLE(\
		/obj/random/tool, \
		/obj/item/stack/cable_coil/random, \
		/obj/random/tank, \
		/obj/random/tech_supply/component, \
		LOOT_STACK(1, /obj/item/stack/material/steel, 25), \
		LOOT_STACK(1, /obj/item/stack/material/glass, 10), \
		LOOT_STACK(1, /obj/item/stack/material/plasteel, 5), \
		/obj/item/mecha_parts/chassis/odysseus, \
		/obj/item/mecha_parts/part/odysseus_head, \
		/obj/item/mecha_parts/part/odysseus_torso, \
		/obj/item/mecha_parts/part/odysseus_left_arm, \
		/obj/item/mecha_parts/part/odysseus_right_arm, \
		/obj/item/mecha_parts/part/odysseus_left_leg, \
		/obj/item/mecha_parts/part/odysseus_right_leg), \
	LOOT_UNCOMMON(20, \
		/obj/item/mecha_parts/mecha_equipment/tool/sleeper, \
		/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun, \
		/obj/item/mecha_parts/mecha_equipment/weapon/ballistic/missile_rack/flare, \
		/obj/item/mecha_parts/mecha_equipment/tool/extinguisher), \
	LOOT_RARE(10, \
		/obj/item/mecha_parts/mecha_equipment/gravcatapult, \
		/obj/item/mecha_parts/mecha_equipment/anticcw_armor_booster, \
		/obj/item/mecha_parts/mecha_equipment/shocker), \
	LOOT_DEPLETION(9, FALSE))

// Gygax loot
DECLARE_LOOT(/loot/mecha/gygax, \
	LOOT_TABLE(\
		/obj/random/tool, \
		/obj/item/stack/cable_coil/random, \
		/obj/random/tank, \
		/obj/random/tech_supply/component, \
		LOOT_STACK(1, /obj/item/stack/material/steel, 25), \
		LOOT_STACK(1, /obj/item/stack/material/glass, 10), \
		LOOT_STACK(1, /obj/item/stack/material/plasteel, 5), \
		/obj/item/mecha_parts/chassis/gygax, \
		/obj/item/mecha_parts/part/gygax_head, \
		/obj/item/mecha_parts/part/gygax_torso, \
		/obj/item/mecha_parts/part/gygax_left_arm, \
		/obj/item/mecha_parts/part/gygax_right_arm, \
		/obj/item/mecha_parts/part/gygax_left_leg, \
		/obj/item/mecha_parts/part/gygax_right_leg, \
		/obj/item/mecha_parts/part/gygax_armour), \
	LOOT_UNCOMMON(20, \
		/obj/item/mecha_parts/mecha_equipment/shocker, \
		/obj/item/mecha_parts/mecha_equipment/weapon/ballistic/missile_rack/grenade, \
		/obj/item/mecha_parts/mecha_equipment/weapon/energy/laser, \
		/obj/item/mecha_parts/mecha_equipment/weapon/energy/taser, \
		/obj/item/kit/paint/gygax, \
		/obj/item/kit/paint/gygax/darkgygax, \
		/obj/item/kit/paint/gygax/recitence), \
	LOOT_RARE(10, \
		/obj/item/mecha_parts/mecha_equipment/tesla_energy_relay, \
		/obj/item/mecha_parts/mecha_equipment/weapon/ballistic/lmg, \
		/obj/item/mecha_parts/mecha_equipment/repair_droid, \
		/obj/item/mecha_parts/mecha_equipment/weapon/energy/laser/heavy), \
	LOOT_DEPLETION(9, FALSE))

// Gygax loot
DECLARE_LOOT(/loot/mecha/durand, \
	LOOT_TABLE(\
		/obj/random/tool, \
		/obj/item/stack/cable_coil/random, \
		/obj/random/tank, \
		/obj/random/tech_supply/component, \
		LOOT_STACK(1, /obj/item/stack/material/steel, 25), \
		LOOT_STACK(1, /obj/item/stack/material/glass, 10), \
		LOOT_STACK(1, /obj/item/stack/material/plasteel, 5), \
		/obj/item/mecha_parts/chassis/durand, \
		/obj/item/mecha_parts/part/durand_head, \
		/obj/item/mecha_parts/part/durand_torso, \
		/obj/item/mecha_parts/part/durand_left_arm, \
		/obj/item/mecha_parts/part/durand_right_arm, \
		/obj/item/mecha_parts/part/durand_left_leg, \
		/obj/item/mecha_parts/part/durand_right_leg, \
		/obj/item/mecha_parts/part/durand_armour), \
	LOOT_UNCOMMON(20, \
		/obj/item/mecha_parts/mecha_equipment/shocker, \
		/obj/item/mecha_parts/mecha_equipment/weapon/ballistic/missile_rack/grenade, \
		/obj/item/mecha_parts/mecha_equipment/weapon/energy/laser, \
		/obj/item/mecha_parts/mecha_equipment/antiproj_armor_booster, \
		/obj/item/kit/paint/durand, \
		/obj/item/kit/paint/durand/seraph, \
		/obj/item/kit/paint/durand/phazon), \
	LOOT_RARE(10, \
		/obj/item/mecha_parts/mecha_equipment/tesla_energy_relay, \
		/obj/item/mecha_parts/mecha_equipment/weapon/ballistic/scattershot, \
		/obj/item/mecha_parts/mecha_equipment/repair_droid, \
		/obj/item/mecha_parts/mecha_equipment/weapon/energy/laser/heavy), \
	LOOT_DEPLETION(9, FALSE))

// Phazon loot
DECLARE_LOOT(/loot/mecha/phazon, \
	LOOT_TABLE(\
		/obj/item/storage/toolbox/syndicate/powertools, \
		LOOT_STACK(1, /obj/item/stack/material/plasteel, 20), \
		LOOT_STACK(1, /obj/item/stack/material/durasteel, 10), \
		/obj/item/mecha_parts/chassis/phazon, \
		/obj/item/mecha_parts/part/phazon_head, \
		/obj/item/mecha_parts/part/phazon_torso, \
		/obj/item/mecha_parts/part/phazon_left_arm, \
		/obj/item/mecha_parts/part/phazon_right_arm, \
		/obj/item/mecha_parts/part/phazon_left_leg, \
		/obj/item/mecha_parts/part/phazon_right_leg), \
	LOOT_UNCOMMON(20, \
		/obj/item/mecha_parts/mecha_equipment/shocker, \
		/obj/item/mecha_parts/mecha_equipment/weapon/energy/flamer/rigged, \
		/obj/item/mecha_parts/mecha_equipment/weapon/energy/laser/heavy, \
		/obj/item/mecha_parts/mecha_equipment/antiproj_armor_booster), \
	LOOT_RARE(10, \
		/obj/item/mecha_parts/mecha_equipment/tesla_energy_relay, \
		/obj/item/mecha_parts/mecha_equipment/weapon/energy/ion, \
		/obj/item/mecha_parts/mecha_equipment/repair_droid, \
		/obj/item/mecha_parts/mecha_equipment/teleporter), \
	LOOT_DEPLETION(9, FALSE))

// Stuff you may find attached to a mouse tank.
DECLARE_LOOT(/loot/mecha/mouse_tank, \
	LOOT_TABLE(\
		/obj/random/tool = 2, \
		/obj/item/stack/cable_coil/random = 1, \
		/obj/random/tank = 1, \
		/obj/random/tech_supply/component = 2, \
		/obj/effect/decal/remains/mouse = 1, \
		LOOT_STACK(1, /obj/item/stack/material/steel, 20)), \
	LOOT_UNCOMMON(20, \
		/obj/item/mecha_parts/mecha_equipment/weapon/ballistic/lmg/rigged, \
		/obj/item/mecha_parts/mecha_equipment/generator), \
	LOOT_RARE(10, \
		/obj/item/mecha_parts/mecha_equipment/weapon/ballistic/lmg, \
		/obj/item/mecha_parts/mecha_equipment/generator/nuclear), \
	LOOT_DEPLETION(5, FALSE))

// Stuff you may find attached to a livewire mouse tank.
DECLARE_LOOT(/loot/mecha/mouse_tank/livewire, \
	LOOT_TABLE(\
		/obj/random/tool = 2, \
		/obj/item/stack/cable_coil/random = 1, \
		/obj/random/tank = 1, \
		/obj/random/tech_supply/component = 2, \
		/obj/effect/decal/remains/mouse = 1, \
		LOOT_STACK(1, /obj/item/stack/material/steel, 20)), \
	LOOT_UNCOMMON(20, \
		/obj/item/mecha_parts/mecha_equipment/weapon/energy/flamer/rigged, \
		/obj/item/mecha_parts/mecha_equipment/tool/extinguisher), \
	LOOT_RARE(10, \
		/obj/item/mecha_parts/mecha_equipment/weapon/energy/flamer, \
		/obj/item/mecha_parts/mecha_equipment/generator), \
	LOOT_DEPLETION(5, FALSE))

// Stuff you may find attached to a eraticator mouse tank.
DECLARE_LOOT(/loot/mecha/mouse_tank/eraticator, \
	LOOT_TABLE(\
		/obj/random/tool = 2, \
		/obj/item/stack/cable_coil/random = 1, \
		/obj/random/tank = 1, \
		/obj/random/tech_supply/component = 2, \
		/obj/effect/decal/remains/mouse = 1, \
		LOOT_STACK(1, /obj/item/stack/material/steel, 20)), \
	LOOT_UNCOMMON(20, \
		/obj/item/ammo_magazine/m75, \
		/obj/item/mecha_parts/mecha_equipment/weapon/ballistic/mortar), \
	LOOT_RARE(10, \
		/obj/item/gun/projectile/gyropistol, \
		/obj/item/mecha_parts/mecha_equipment/generator/nuclear), \
	LOOT_DEPLETION(5, FALSE))

// Stuff you may find attached to an odd gygax.
DECLARE_LOOT(/loot/mecha/odd_gygax, \
	LOOT_TABLE(\
		/obj/random/tool = 2, \
		/obj/item/stack/cable_coil/random = 1, \
		/obj/random/tank = 1, \
		/obj/random/tech_supply/component = 2, \
		LOOT_STACK(1, /obj/item/stack/material/steel, 20)), \
	LOOT_UNCOMMON(20, \
		/obj/item/holosign_creator/smokewand, \
		/obj/item/holosign_creator/forcewand), \
	LOOT_RARE(10, \
		/obj/item/weldingtool/alien, \
		/obj/item/cell/slime/jellyfish), \
	LOOT_DEPLETION(0, FALSE))

// Stuff you may find attached to an odd gygax.
DECLARE_LOOT(/loot/mecha/odd_riplay, \
	LOOT_TABLE(\
		/obj/random/tool = 2, \
		/obj/item/stack/cable_coil/random = 1, \
		/obj/random/tank = 1, \
		/obj/random/tech_supply/component = 2, \
		LOOT_STACK(1, /obj/item/stack/material/steel, 20)), \
	LOOT_UNCOMMON(30, \
		LOOT_STACK(1, /obj/item/stack/material/durasteel, 10), \
		LOOT_STACK(1, /obj/item/stack/material/morphium, 5)), \
	LOOT_RARE(20, \
		/obj/item/clothing/suit/armor/reactive, \
		/obj/item/personal_shield_generator/belt/magnetbelt), \
	LOOT_DEPLETION(0, FALSE))
