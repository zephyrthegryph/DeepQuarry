/obj/random/gun/random
	name = "Random Weapon"
	desc = "This is a random energy or ballistic weapon."
	icon_state = "gun"

DECLARE_LOOT(/obj/random/gun/random, LOOT_TABLE(/obj/random/energy, /obj/random/projectile/random))

/obj/random/energy
	name = "Random Energy Weapon"
	desc = "This is a random energy weapon."
	icon_state = "gun_energy"

DECLARE_LOOT(/obj/random/energy, LOOT_TABLE(\
	/obj/item/gun/energy/laser = 3, \
	/obj/item/gun/energy/laser/sleek = 3, \
	/obj/item/gun/energy/gun = 4, \
	/obj/item/gun/energy/gun/burst = 3, \
	/obj/item/gun/energy/gun/nuclear = 1, \
	/obj/item/gun/energy/retro = 2, \
	/obj/item/gun/energy/lasercannon = 2, \
	/obj/item/gun/energy/xray = 3, \
	/obj/item/gun/energy/sniperrifle = 1, \
	/obj/item/gun/energy/plasmastun = 1, \
	/obj/item/gun/energy/ionrifle = 2, \
	/obj/item/gun/energy/ionrifle/pistol = 2, \
	/obj/item/gun/energy/toxgun = 3, \
	/obj/item/gun/energy/taser = 3, \
	/obj/item/gun/energy/crossbow/largecrossbow = 2, \
	/obj/item/gun/energy/stunrevolver = 3, \
	/obj/item/gun/energy/stunrevolver/vintage = 2, \
	/obj/item/gun/energy/gun/compact = 3))

/obj/random/energy/highend
	name = "Random Energy Weapon"
	desc = "This is a random, actually good energy weapon."
	icon_state = "gun_energy_2"

DECLARE_LOOT(/obj/random/energy/highend, LOOT_TABLE(\
	/obj/item/gun/energy/laser = 3, \
	/obj/item/gun/energy/laser/sleek = 3, \
	/obj/item/gun/energy/gun = 4, \
	/obj/item/gun/energy/gun/burst = 3, \
	/obj/item/gun/energy/gun/nuclear = 1, \
	/obj/item/gun/energy/retro = 2, \
	/obj/item/gun/energy/lasercannon = 2, \
	/obj/item/gun/energy/xray = 3, \
	/obj/item/gun/energy/sniperrifle = 1, \
	/obj/item/gun/energy/crossbow/largecrossbow = 2, \
	/obj/item/gun/energy/gun/compact = 3))

/obj/random/energy/sec
	name = "Random Security Energy Weapon"
	desc = "This is a random security weapon."
	icon_state = "gun_energy"

DECLARE_LOOT(/obj/random/energy/sec, LOOT_TABLE(/obj/item/gun/energy/laser, /obj/item/gun/energy/gun))

/obj/random/projectile
	name = "Random Projectile Weapon"
	desc = "This is a random projectile weapon."
	icon_state = "gun"

DECLARE_LOOT(/obj/random/projectile, LOOT_TABLE(\
	/obj/item/gun/projectile/automatic/wt550 = 3, \
	/obj/item/gun/projectile/automatic/mini_uzi = 3, \
	/obj/item/gun/projectile/automatic/tommygun = 3, \
	/obj/item/gun/projectile/automatic/c20r = 2, \
	/obj/item/gun/projectile/automatic/sts35 = 2, \
	/obj/item/gun/projectile/automatic/z8 = 2, \
	/obj/item/gun/projectile/automatic/combatsmg = 2, \
	/obj/item/gun/projectile/colt = 4, \
	/obj/item/gun/projectile/deagle = 2, \
	/obj/item/gun/projectile/deagle/camo = 1, \
	/obj/item/gun/projectile/deagle/gold = 1, \
	/obj/item/gun/projectile/derringer = 3, \
	/obj/item/gun/projectile/heavysniper = 1, \
	/obj/item/gun/projectile/luger = 4, \
	/obj/item/gun/projectile/luger/brown = 3, \
	/obj/item/gun/projectile/sec = 4, \
	/obj/item/gun/projectile/sec/wood = 3, \
	/obj/item/gun/projectile/p92x = 4, \
	/obj/item/gun/projectile/p92x/brown = 3, \
	/obj/item/gun/projectile/pistol = 4, \
	/obj/item/gun/projectile/pirate = 5, \
	/obj/item/gun/projectile/revolver = 2, \
	/obj/item/gun/projectile/revolver/deckard = 4, \
	/obj/item/gun/projectile/revolver/detective = 4, \
	/obj/item/gun/projectile/revolver/judge = 2, \
	/obj/item/gun/projectile/revolver/lemat = 3, \
	/obj/item/gun/projectile/revolver/mateba = 2, \
	/obj/item/gun/projectile/shotgun/doublebarrel = 4, \
	/obj/item/gun/projectile/shotgun/doublebarrel/sawn = 3, \
	/obj/item/gun/projectile/shotgun/pump = 3, \
	/obj/item/gun/projectile/shotgun/pump/combat = 2, \
	/obj/item/gun/projectile/shotgun/pump/rifle = 4, \
	/obj/item/gun/projectile/shotgun/pump/rifle/lever = 3, \
	/obj/item/gun/projectile/shotgun/semi = 2, \
	/obj/item/gun/projectile/silenced = 2))

/obj/random/projectile/sec
	name = "Random Security Projectile Weapon"
	desc = "This is a random security weapon."
	icon_state = "gun_shotgun"

DECLARE_LOOT(/obj/random/projectile/sec, LOOT_TABLE(\
	/obj/item/gun/projectile/shotgun/pump = 3, \
	/obj/item/gun/projectile/automatic/wt550 = 2, \
	/obj/item/gun/projectile/shotgun/pump/combat = 1))

/obj/random/projectile/shotgun
	name = "Random Shotgun"
	desc = "This is a random shotgun-type weapon."
	icon_state = "gun_shotgun"

DECLARE_LOOT(/obj/random/projectile/shotgun, LOOT_TABLE(\
	/obj/item/gun/projectile/shotgun/doublebarrel = 4, \
	/obj/item/gun/projectile/shotgun/doublebarrel/sawn = 3, \
	/obj/item/gun/projectile/shotgun/pump = 3, \
	/obj/item/gun/projectile/shotgun/pump/combat = 1, \
	/obj/item/gun/projectile/shotgun/semi = 1))

/obj/random/handgun
	name = "Random Handgun"
	desc = "This is a random sidearm."
	icon_state = "gun"

DECLARE_LOOT(/obj/random/handgun, LOOT_TABLE(\
	/obj/item/gun/projectile/sec = 4, \
	/obj/item/gun/projectile/p92x = 4, \
	/obj/item/gun/projectile/sec/wood = 3, \
	/obj/item/gun/projectile/p92x/brown = 3, \
	/obj/item/gun/projectile/colt = 3, \
	/obj/item/gun/projectile/luger = 2, \
	/obj/item/gun/energy/gun = 2, \
	/obj/item/gun/projectile/pistol = 2, \
	/obj/item/gun/energy/retro = 1, \
	/obj/item/gun/projectile/luger/brown = 1))

/obj/random/handgun/sec
	name = "Random Security Handgun"
	desc = "This is a random security sidearm."
	icon_state = "gun"

DECLARE_LOOT(/obj/random/handgun/sec, LOOT_TABLE(/obj/item/gun/projectile/sec = 3, /obj/item/gun/projectile/sec/wood = 1))

/obj/random/ammo
	name = "Random Ammunition"
	desc = "This is random security ammunition."
	icon_state = "ammo"

DECLARE_LOOT(/obj/random/ammo, LOOT_TABLE(\
	/obj/item/ammo_magazine/ammo_box/b12g/beanbag = 6, \
	/obj/item/ammo_magazine/ammo_box/b12g = 2, \
	/obj/item/ammo_magazine/ammo_box/b12g/pellet = 4, \
	/obj/item/ammo_magazine/ammo_box/b12g/stunshell = 1, \
	/obj/item/ammo_magazine/m45 = 2, \
	/obj/item/ammo_magazine/m45/rubber = 4, \
	/obj/item/ammo_magazine/m45/flash = 4, \
	/obj/item/ammo_magazine/m9mmt = 2, \
	/obj/item/ammo_magazine/m9mmt/rubber = 6))

/obj/random/grenade
	name = "Random Grenade"
	desc = "This is random thrown grenades (no C4/etc.)."
	icon_state = "grenade_2"

DECLARE_LOOT(/obj/random/grenade, LOOT_TABLE(\
	/obj/item/grenade/concussion = 15, \
	/obj/item/grenade/empgrenade = 5, \
	/obj/item/grenade/empgrenade/low_yield = 15, \
	/obj/item/grenade/chem_grenade/metalfoam = 5, \
	/obj/item/grenade/chem_grenade/incendiary = 2, \
	/obj/item/grenade/chem_grenade/antiweed = 10, \
	/obj/item/grenade/chem_grenade/cleaner = 10, \
	/obj/item/grenade/chem_grenade/teargas = 10, \
	/obj/item/grenade/explosive = 5, \
	/obj/item/grenade/explosive/mini = 10, \
	/obj/item/grenade/explosive/frag = 2, \
	/obj/item/grenade/flashbang = 15, \
	/obj/item/grenade/flashbang/clusterbang = 1, \
	/obj/item/grenade/shooter/rubber = 15, \
	/obj/item/grenade/shooter/energy/flash = 10, \
	/obj/item/grenade/smokebomb = 15))

/obj/random/grenade/lethal
	name = "Random Grenade"
	desc = "This is random thrown grenade that hurts a lot."
	icon_state = "grenade_3"

DECLARE_LOOT(/obj/random/grenade/lethal, LOOT_TABLE(\
	/obj/item/grenade/concussion = 15, \
	/obj/item/grenade/empgrenade = 5, \
	/obj/item/grenade/chem_grenade/incendiary = 2, \
	/obj/item/grenade/explosive = 5, \
	/obj/item/grenade/explosive/mini = 10, \
	/obj/item/grenade/explosive/frag = 2))

/obj/random/grenade/less_lethal
	name = "Random Security Grenade"
	desc = "This is a random thrown grenade that shouldn't kill anyone."
	icon_state = "grenade"

DECLARE_LOOT(/obj/random/grenade/less_lethal, LOOT_TABLE(\
	/obj/item/grenade/concussion = 20, \
	/obj/item/grenade/empgrenade/low_yield = 15, \
	/obj/item/grenade/chem_grenade/metalfoam = 15, \
	/obj/item/grenade/chem_grenade/teargas = 20, \
	/obj/item/grenade/flashbang = 20, \
	/obj/item/grenade/flashbang/clusterbang = 1, \
	/obj/item/grenade/shooter/rubber = 15, \
	/obj/item/grenade/shooter/energy/flash = 10))

/obj/random/grenade/box
	name = "Random Grenade Box"
	desc = "This is a random box of grenades. Not to be mistaken for a box of random grenades. Or a grenade of random boxes - but that would just be silly."
	icon_state = "grenade_box"

DECLARE_LOOT(/obj/random/grenade/box, LOOT_TABLE(\
	/obj/item/storage/box/flashbangs = 20, \
	/obj/item/storage/box/emps = 10, \
	/obj/item/storage/box/empslite = 20, \
	/obj/item/storage/box/smokes = 15, \
	/obj/item/storage/box/anti_photons = 5, \
	/obj/item/storage/box/frags = 5, \
	/obj/item/storage/box/metalfoam = 10, \
	/obj/item/storage/box/teargas = 15))

/obj/random/projectile/random
	name = "Random Projectile Weapon"
	desc = "This is a random projectile weapon."
	icon_state = "gun_2"

DECLARE_LOOT(/obj/random/projectile/random, LOOT_TABLE(\
	/obj/random/multiple/gun/projectile/handgun = 3, \
	/obj/random/multiple/gun/projectile/smg = 2, \
	/obj/random/multiple/gun/projectile/shotgun = 2, \
	/obj/random/multiple/gun/projectile/rifle = 1))

/obj/random/multiple/gun/projectile/smg
	name = "random smg projectile gun"
	desc = "Loot for PoIs."
	icon_state = "gun_auto"

DECLARE_LOOT(/obj/random/multiple/gun/projectile/smg, LOOT_TABLE(\
	LOOT_SET(3, /obj/item/gun/projectile/automatic/wt550, /obj/item/ammo_magazine/m9mmt, /obj/item/ammo_magazine/m9mmt), \
	LOOT_SET(3, /obj/item/gun/projectile/automatic/mini_uzi, /obj/item/ammo_magazine/m45uzi, /obj/item/ammo_magazine/m45uzi), \
	LOOT_SET(3, /obj/item/gun/projectile/automatic/tommygun, /obj/item/ammo_magazine/m45tommy, /obj/item/ammo_magazine/m45tommy), \
	LOOT_SET(2, /obj/item/gun/projectile/automatic/c20r, /obj/item/ammo_magazine/m10mm, /obj/item/ammo_magazine/m10mm), \
	LOOT_SET(1, /obj/item/gun/projectile/automatic/p90, /obj/item/ammo_magazine/m9mmp90), \
	LOOT_SET(3, /obj/item/gun/projectile/automatic/combatsmg, /obj/item/ammo_magazine/m9mmt, /obj/item/ammo_magazine/m9mmt)))

/obj/random/multiple/gun/projectile/rifle
	name = "random rifle projectile gun"
	desc = "Loot for PoIs."
	icon_state = "gun_rifle"

//Concerns about the bullpup, but currently seems to be only a slightly stronger z8. But we shall see.

DECLARE_LOOT(/obj/random/multiple/gun/projectile/rifle, LOOT_TABLE(\
	LOOT_SET(2, /obj/item/gun/projectile/automatic/sts35, /obj/item/ammo_magazine/m545, /obj/item/ammo_magazine/m545), \
	LOOT_SET(2, /obj/item/gun/projectile/automatic/z8, /obj/item/ammo_magazine/m762, /obj/item/ammo_magazine/m762), \
	LOOT_SET(4, /obj/item/gun/projectile/shotgun/pump/rifle, /obj/item/ammo_magazine/clip/c762, /obj/item/ammo_magazine/clip/c762), \
	LOOT_SET(3, /obj/item/gun/projectile/shotgun/pump/rifle/lever, /obj/item/ammo_magazine/clip/c762, /obj/item/ammo_magazine/clip/c762), \
	LOOT_SET(1, /obj/item/gun/projectile/garand, /obj/item/ammo_magazine/m762enbloc, /obj/item/ammo_magazine/m762enbloc), \
	LOOT_SET(1, /obj/item/gun/projectile/revolvingrifle, /obj/item/ammo_magazine/s44/rifle, /obj/item/ammo_magazine/s44/rifle), \
	LOOT_SET(1, /obj/item/gun/projectile/automatic/bullpup, /obj/item/ammo_magazine/m762, /obj/item/ammo_magazine/m762), \
	LOOT_SET(1, /obj/item/gun/projectile/caseless/prototype, /obj/item/ammo_magazine/m5mmcaseless, /obj/item/ammo_magazine/m5mmcaseless)))

/obj/random/multiple/gun/projectile/handgun
	name = "random handgun projectile gun"
	desc = "Loot for PoIs."
	icon_state = "gun"

DECLARE_LOOT(/obj/random/multiple/gun/projectile/handgun, LOOT_TABLE(\
	LOOT_SET(5, /obj/item/gun/projectile/colt, /obj/item/ammo_magazine/m45, /obj/item/ammo_magazine/m45), \
	LOOT_SET(4, /obj/item/gun/projectile/contender, /obj/item/ammo_magazine/s357, /obj/item/ammo_magazine/s357), \
	LOOT_SET(3, /obj/item/gun/projectile/contender/tacticool, /obj/item/ammo_magazine/s357, /obj/item/ammo_magazine/s357), \
	LOOT_SET(2, /obj/item/gun/projectile/deagle, /obj/item/ammo_magazine/m44, /obj/item/ammo_magazine/m44), \
	LOOT_SET(1, /obj/item/gun/projectile/deagle/camo, /obj/item/ammo_magazine/m44, /obj/item/ammo_magazine/m44), \
	LOOT_SET(1, /obj/item/gun/projectile/deagle/gold, /obj/item/ammo_magazine/m44, /obj/item/ammo_magazine/m44), \
	LOOT_SET(4, /obj/item/gun/projectile/derringer, /obj/item/ammo_magazine/s357, /obj/item/ammo_magazine/s357), \
	LOOT_SET(5, /obj/item/gun/projectile/luger, /obj/item/ammo_magazine/m9mm/luger, /obj/item/ammo_magazine/m9mm/luger), \
	LOOT_SET(4, /obj/item/gun/projectile/luger/brown, /obj/item/ammo_magazine/m9mm/compact, /obj/item/ammo_magazine/m9mm/compact), \
	LOOT_SET(5, /obj/item/gun/projectile/sec, /obj/item/ammo_magazine/m45, /obj/item/ammo_magazine/m45), \
	LOOT_SET(4, /obj/item/gun/projectile/sec/wood, /obj/item/ammo_magazine/m45, /obj/item/ammo_magazine/m45), \
	LOOT_SET(5, /obj/item/gun/projectile/p92x, /obj/item/ammo_magazine/m9mm, /obj/item/ammo_magazine/m9mm), \
	LOOT_SET(4, /obj/item/gun/projectile/p92x/brown, /obj/item/ammo_magazine/m9mm, /obj/item/ammo_magazine/m9mm), \
	LOOT_SET(2, /obj/item/gun/projectile/p92x/large, /obj/item/ammo_magazine/m9mm/large, /obj/item/ammo_magazine/m9mm/large), \
	LOOT_SET(5, /obj/item/gun/projectile/pistol, /obj/item/ammo_magazine/m9mm/compact, /obj/item/ammo_magazine/m9mm/compact), \
	LOOT_SET(2, /obj/item/gun/projectile/silenced, /obj/item/ammo_magazine/m45, /obj/item/ammo_magazine/m45), \
	LOOT_SET(2, /obj/item/gun/projectile/revolver, /obj/item/ammo_magazine/s357, /obj/item/ammo_magazine/s357), \
	LOOT_SET(4, /obj/item/gun/projectile/revolver/deckard, /obj/item/ammo_magazine/s38, /obj/item/ammo_magazine/s38), \
	LOOT_SET(4, /obj/item/gun/projectile/revolver/detective, /obj/item/ammo_magazine/s38, /obj/item/ammo_magazine/s38), \
	LOOT_SET(2, /obj/item/gun/projectile/revolver/judge, /obj/item/ammo_magazine/clip/c12g, /obj/item/ammo_magazine/clip/c12g, /obj/item/ammo_magazine/clip/c12g), \
	LOOT_SET(2, /obj/item/gun/projectile/revolver/lemat, /obj/item/ammo_magazine/s38, /obj/item/ammo_magazine/s38, /obj/item/ammo_magazine/clip/c12g), \
	LOOT_SET(2, /obj/item/gun/projectile/revolver/mateba, /obj/item/ammo_magazine/s357, /obj/item/ammo_magazine/s357), \
	LOOT_SET(2, /obj/item/gun/projectile/revolver/webley, /obj/item/ammo_magazine/s44, /obj/item/ammo_magazine/s44), \
	LOOT_SET(1, /obj/item/gun/projectile/revolver/consul, /obj/item/ammo_magazine/s44/rubber, /obj/item/ammo_magazine/s44/rubber)))

/obj/random/multiple/gun/projectile/shotgun
	name = "random shotgun projectile gun"
	desc = "Loot for PoIs."
	icon_state = "gun_shotgun"

DECLARE_LOOT(/obj/random/multiple/gun/projectile/shotgun, LOOT_TABLE(\
	LOOT_SET(4, /obj/item/gun/projectile/shotgun/doublebarrel/pellet, /obj/item/ammo_magazine/clip/c12g/pellet, /obj/item/ammo_magazine/clip/c12g/pellet, /obj/item/ammo_magazine/clip/c12g/pellet, /obj/item/ammo_magazine/clip/c12g/pellet), \
	LOOT_SET(3, /obj/item/gun/projectile/shotgun/doublebarrel/sawn, /obj/item/ammo_magazine/clip/c12g/pellet, /obj/item/ammo_magazine/clip/c12g/pellet, /obj/item/ammo_magazine/clip/c12g/pellet, /obj/item/ammo_magazine/clip/c12g/pellet), \
	LOOT_SET(3, /obj/item/gun/projectile/shotgun/pump/slug, /obj/item/ammo_magazine/ammo_box/b12g), \
	LOOT_SET(1, /obj/item/gun/projectile/shotgun/pump/combat, /obj/item/ammo_magazine/ammo_box/b12g), \
	LOOT_SET(1, /obj/item/gun/projectile/shotgun/semi, /obj/item/ammo_magazine/ammo_box/b12g)))

// Not strictly a gun, but is used in PoIs to spawn the dropped guns of mercs, or a busted version.
/obj/random/projectile/scrapped_gun
	name = "broken gun spawner"
	desc = "Spawns a random broken gun, or rarely a fully functional one."
	icon_state = "gun_scrap"

DECLARE_LOOT(/obj/random/projectile/scrapped_gun, LOOT_TABLE(\
	/obj/random/projectile/scrapped_pistol = 10, \
	/obj/random/projectile/scrapped_smg = 5, \
	/obj/random/projectile/scrapped_laser = 5, \
	/obj/random/projectile/scrapped_shotgun = 3, \
	/obj/random/projectile/scrapped_ionrifle = 3, \
	/obj/random/projectile/scrapped_bulldog = 1, \
	/obj/random/projectile/scrapped_flechette = 1, \
	/obj/random/projectile/scrapped_grenadelauncher = 1, \
	/obj/random/projectile/scrapped_dartgun = 1))

/obj/random/projectile/scrapped_shotgun
	name = "broken shotgun spawner"
	desc = "Loot for PoIs, or their mobs."
	icon_state = "gun_scrap"

DECLARE_LOOT(/obj/random/projectile/scrapped_shotgun, LOOT_TABLE(\
	/obj/item/broken_gun/pumpshotgun = 10, \
	/obj/item/broken_gun/pumpshotgun_combat = 5, \
	/obj/item/gun/projectile/shotgun/pump = 3, \
	/obj/item/gun/projectile/shotgun/pump/combat = 1))

/obj/random/projectile/scrapped_smg
	name = "broken smg spawner"
	desc = "Loot for PoIs, or their mobs."
	icon_state = "gun_scrap"

DECLARE_LOOT(/obj/random/projectile/scrapped_smg, LOOT_TABLE(/obj/item/broken_gun/c20r = 10, /obj/item/gun/projectile/automatic/c20r = 3))

/obj/random/projectile/scrapped_pistol
	name = "broken pistol spawner"
	desc = "Loot for PoIs, or their mobs."
	icon_state = "gun_scrap"

DECLARE_LOOT(/obj/random/projectile/scrapped_pistol, LOOT_TABLE(/obj/item/broken_gun/silenced45 = 10, /obj/item/gun/projectile/silenced = 3))

/obj/random/projectile/scrapped_laser
	name = "broken laser spawner"
	desc = "Loot for PoIs, or their mobs."
	icon_state = "gun_scrap"

DECLARE_LOOT(/obj/random/projectile/scrapped_laser, LOOT_TABLE(\
	/obj/item/broken_gun/laserrifle = 10, \
	/obj/item/broken_gun/laser_retro = 5, \
	/obj/item/gun/energy/laser = 3, \
	/obj/item/gun/energy/retro = 1))

/obj/random/projectile/scrapped_ionrifle
	name = "broken ionrifle spawner"
	desc = "Loot for PoIs, or their mobs."
	icon_state = "gun_scrap"

DECLARE_LOOT(/obj/random/projectile/scrapped_ionrifle, LOOT_TABLE(/obj/item/broken_gun/ionrifle = 10, /obj/item/gun/energy/ionrifle = 3))

/obj/random/projectile/scrapped_bulldog
	name = "broken z8 spawner"
	desc = "Loot for PoIs, or their mobs."
	icon_state = "gun_scrap"

DECLARE_LOOT(/obj/random/projectile/scrapped_bulldog, LOOT_TABLE(/obj/item/broken_gun/z8 = 10, /obj/item/gun/projectile/automatic/z8 = 3))

/obj/random/projectile/scrapped_flechette
	name = "broken flechette spawner"
	desc = "Loot for PoIs, or their mobs."
	icon_state = "gun_scrap"

DECLARE_LOOT(/obj/random/projectile/scrapped_flechette, LOOT_TABLE(/obj/item/broken_gun/flechette = 10, /obj/item/gun/magnetic/railgun/flechette = 3))

/obj/random/projectile/scrapped_grenadelauncher
	name = "broken grenadelauncher spawner"
	desc = "Loot for PoIs, or their mobs."
	icon_state = "gun_scrap"

DECLARE_LOOT(/obj/random/projectile/scrapped_grenadelauncher, LOOT_TABLE(/obj/item/broken_gun/grenadelauncher = 10, /obj/item/gun/launcher/grenade = 3))

/obj/random/projectile/scrapped_dartgun
	name = "broken dartgun spawner"
	desc = "Loot for PoIs, or their mobs."
	icon_state = "gun_scrap"

DECLARE_LOOT(/obj/random/projectile/scrapped_dartgun, LOOT_TABLE(/obj/item/broken_gun/dartgun = 10, /obj/item/gun/projectile/dartgun = 3))
