/*
 * Random Mobs
 */

/obj/random/mob
	name = "Random Animal"
	desc = "This is a random animal."
	icon_state = "animal"

	var/overwrite_hostility = 0

	var/mob_faction = null
	var/mob_returns_home = 0
	var/mob_wander = 1
	var/mob_wander_distance = 3
	var/mob_hostile = 0
	var/mob_retaliate = 0
	var/mob_ghostjoin = 0 //Should be a number between 0 and 100, dictates the probability of that mob being ghost joinable.

CAPABILITIES(/obj/random/mob)
	configure(map_resolver(
		vars = list(
			"drop_get_turf", "overwrite_hostility", "mob_faction", "mob_returns_home",
			"mob_wander", "mob_wander_distance", "mob_hostile", "mob_ghostjoin")))
	loot(
		table = list(
			/mob/living/simple_mob/animal/passive/lizard = 10,
			/mob/living/simple_mob/animal/sif/diyaab = 6,
			/mob/living/simple_mob/animal/passive/cat = 16,
			/mob/living/simple_mob/animal/passive/dog/corgi = 10,
			/mob/living/simple_mob/animal/passive/dog/corgi/puppy = 6,
			/mob/living/simple_mob/animal/passive/crab = 11,
			/mob/living/simple_mob/animal/passive/chicken = 10,
			/mob/living/simple_mob/animal/passive/chick = 6,
			/mob/living/simple_mob/animal/passive/cow = 10,
			/mob/living/simple_mob/animal/goat = 6,
			/mob/living/simple_mob/animal/passive/penguin = 10,
			/mob/living/simple_mob/animal/passive/mouse = 10,
			/mob/living/simple_mob/animal/passive/mothroach = 10,
			/mob/living/simple_mob/animal/passive/yithian = 10,
			/mob/living/simple_mob/animal/passive/tindalos = 10,
			/mob/living/simple_mob/animal/passive/pillbug = 10,
			/mob/living/simple_mob/animal/passive/dog/tamaskan = 10,
			/mob/living/simple_mob/animal/passive/dog/brittany = 10,
			/mob/living/simple_mob/animal/passive/bird/parrot = 3),
		hook = GLOBAL_PROC_REF(loot_hook_random_mob))


/// LOOT_HOOK for /obj/random/mob: sets up each spawned simple mob from the spawner's vars (its map
/// varedits over its type's defaults). Multiple-mob spawners set only the AI and offset.
/proc/loot_hook_random_mob(atom/spawned, path, list/varedits, datum/loot_rng/rng)
	var/mob/living/simple_mob/M = spawned
	if(!istype(M))
		return
	var/obj/random/mob/P = path
	if(M.ai_brain)
		var/datum/ai_brain/AI = M.ai_brain
		AI.go_sleep() //Don't fight eachother while we're still setting up!
		AI.returns_home = MAP_VAR(P, varedits, mob_returns_home)
		AI.wander = MAP_VAR(P, varedits, mob_wander)
		AI.max_home_distance = MAP_VAR(P, varedits, mob_wander_distance)
		if(MAP_VAR(P, varedits, overwrite_hostility))
			AI.set_hostile(MAP_VAR(P, varedits, mob_hostile))
		AI.go_wake() //Now you can kill eachother if your faction didn't override.
	if(ispath(path, /obj/random/mob/multiple))
		return
	var/faction = MAP_VAR(P, varedits, mob_faction)
	if(faction)
		M.faction = faction
	var/ghostjoin = MAP_VAR(P, varedits, mob_ghostjoin)
	if(ghostjoin && rng.chance(ghostjoin))
		M.set_ghostjoin(1)

/obj/random/mob/sif
	name = "Random Sif Animal"
	desc = "This is a random cold weather animal."
	icon_state = "animal"

	mob_returns_home = 1
	mob_wander_distance = 10

CAPABILITIES(/obj/random/mob/sif)
	configure(loot(
		table = list(
			/mob/living/simple_mob/animal/sif/diyaab = 30,
			/mob/living/simple_mob/animal/passive/hare = 20,
			/mob/living/simple_mob/animal/passive/crab = 35,
			/mob/living/simple_mob/animal/passive/penguin = 15,
			/mob/living/simple_mob/animal/passive/mouse = 15,
			/mob/living/simple_mob/animal/passive/dog/tamaskan = 15,
			/mob/living/simple_mob/animal/sif/siffet = 10,
			/mob/living/simple_mob/animal/giant_spider/frost = 2,
			/mob/living/simple_mob/animal/space/goose = 1)))


/obj/random/mob/sif/peaceful
	name = "Random Peaceful Sif Animal"
	desc = "This is a random peaceful cold weather animal."
	icon_state = "animal_passive"

	mob_returns_home = 1
	mob_wander_distance = 12

CAPABILITIES(/obj/random/mob/sif/peaceful)
	configure(loot(
		table = list(
			/mob/living/simple_mob/animal/sif/diyaab = 30,
			/mob/living/simple_mob/animal/passive/hare = 20,
			/mob/living/simple_mob/animal/passive/crab = 15,
			/mob/living/simple_mob/animal/passive/penguin = 15,
			/mob/living/simple_mob/animal/passive/mouse = 15,
			/mob/living/simple_mob/animal/passive/dog/tamaskan = 15,
			/mob/living/simple_mob/animal/sif/hooligan_crab = 20)))

/obj/random/mob/sif/hostile
	name = "Random Hostile Sif Animal"
	desc = "This is a random hostile cold weather animal."
	icon_state = "animal_hostile"

CAPABILITIES(/obj/random/mob/sif/hostile)
	configure(loot(
		table = list(
			/mob/living/simple_mob/animal/sif/savik = 22,
			/mob/living/simple_mob/animal/giant_spider/frost = 33,
			/mob/living/simple_mob/animal/sif/frostfly = 20,
			/mob/living/simple_mob/animal/sif/tymisian = 10,
			/mob/living/simple_mob/animal/sif/shantak = 45)))

/obj/random/mob/sif/kururak
	name = "Random Kururak"
	desc = "This is a random kururak, either waking or hibernating. Will be hostile if more than one are waking."
	icon_state = "frost"

CAPABILITIES(/obj/random/mob/sif/kururak)
	configure(loot(table = list(/mob/living/simple_mob/animal/sif/kururak/hibernate = 1, /mob/living/simple_mob/animal/sif/kururak = 20)))

/obj/random/mob/spider
	name = "Random Spider" //Spiders should patrol where they spawn.
	desc = "This is a random boring spider."
	icon_state = "guard"

	mob_returns_home = 1
	mob_wander_distance = 4

CAPABILITIES(/obj/random/mob/spider)
	configure(loot(table = list(/mob/living/simple_mob/animal/giant_spider/hunter = 33, /mob/living/simple_mob/animal/giant_spider = 45)))

/obj/random/mob/spider/nurse
	name = "Random Nurse Spider"
	desc = "This is a random nurse spider."
	icon_state = "nurse"

	mob_returns_home = 1
	mob_wander_distance = 4

CAPABILITIES(/obj/random/mob/spider/nurse)
	configure(loot(table = list(/mob/living/simple_mob/animal/giant_spider/nurse/hat = 22, /mob/living/simple_mob/animal/giant_spider/nurse = 45)))

/obj/random/mob/spider/mutant
	name = "Random Mutant Spider"
	desc = "This is a random mutated spider."
	icon_state = "phoron"

CAPABILITIES(/obj/random/mob/spider/mutant)
	configure(loot(
		table = list(
			/obj/random/mob/spider = 5,
			/mob/living/simple_mob/animal/giant_spider/webslinger = 10,
			/mob/living/simple_mob/animal/giant_spider/carrier = 10,
			/mob/living/simple_mob/animal/giant_spider/lurker = 33,
			/mob/living/simple_mob/animal/giant_spider/tunneler = 33,
			/mob/living/simple_mob/animal/giant_spider/pepper = 40,
			/mob/living/simple_mob/animal/giant_spider/thermic = 20,
			/mob/living/simple_mob/animal/giant_spider/electric = 40,
			/mob/living/simple_mob/animal/giant_spider/phorogenic = 1,
			/mob/living/simple_mob/animal/giant_spider/frost = 40)))

/obj/random/mob/robotic
	name = "Random Robot Mob"
	desc = "This is a random robot."
	icon_state = "robot"

	overwrite_hostility = 1

	mob_faction = FACTION_MALF_DRONE
	mob_returns_home = 1
	mob_wander = 1
	mob_wander_distance = 5
	mob_hostile = 1
	mob_retaliate = 1

CAPABILITIES(/obj/random/mob/robotic)
	configure(loot(
		table = list(
			/mob/living/simple_mob/mechanical/combat_drone/lesser = 60,
			/mob/living/simple_mob/mechanical/combat_drone = 50,
			/mob/living/simple_mob/mechanical/mining_drone = 50,
			/mob/living/simple_mob/mechanical/mecha/ripley = 15,
			/mob/living/simple_mob/mechanical/mecha/odysseus = 15,
			/mob/living/simple_mob/mechanical/hivebot = 10,
			/mob/living/simple_mob/mechanical/hivebot/swarm = 15,
			/mob/living/simple_mob/mechanical/hivebot/ranged_damage = 10,
			/mob/living/simple_mob/mechanical/hivebot/ranged_damage/rapid = 5,
			/mob/living/simple_mob/mechanical/hivebot/ranged_damage/ion = 5,
			/mob/living/simple_mob/mechanical/hivebot/ranged_damage/laser = 5,
			/mob/living/simple_mob/mechanical/hivebot/ranged_damage/strong = 5,
			/mob/living/simple_mob/mechanical/hivebot/ranged_damage/strong/guard = 5)))

/obj/random/mob/robotic/drone
	name = "Random Drone"
	desc = "This is a random drone."
	icon_state = "drone_dead"

	overwrite_hostility = 1

	mob_faction = FACTION_MALF_DRONE
	mob_returns_home = 1
	mob_wander = 1
	mob_wander_distance = 5
	mob_hostile = 1
	mob_retaliate = 1

CAPABILITIES(/obj/random/mob/robotic/drone)
	configure(loot(
		table = list(
			/mob/living/simple_mob/mechanical/combat_drone/lesser = 6,
			/mob/living/simple_mob/mechanical/combat_drone = 1,
			/mob/living/simple_mob/mechanical/mining_drone = 3)))

/obj/random/mob/robotic/hivebot
	name = "Random Hivebot"
	desc = "This is a random hivebot."
	icon_state = "robot"

	mob_faction = FACTION_HIVEBOT

CAPABILITIES(/obj/random/mob/robotic/hivebot)
	configure(loot(
		table = list(
			/mob/living/simple_mob/mechanical/hivebot = 10,
			/mob/living/simple_mob/mechanical/hivebot/swarm = 15,
			/mob/living/simple_mob/mechanical/hivebot/ranged_damage = 10,
			/mob/living/simple_mob/mechanical/hivebot/ranged_damage/rapid = 5,
			/mob/living/simple_mob/mechanical/hivebot/ranged_damage/ion = 5,
			/mob/living/simple_mob/mechanical/hivebot/ranged_damage/laser = 5,
			/mob/living/simple_mob/mechanical/hivebot/ranged_damage/strong = 5,
			/mob/living/simple_mob/mechanical/hivebot/ranged_damage/strong/guard = 5)))

//Mice

/obj/random/mob/mouse
	name = "Random Mouse"
	desc = "This is a random boring maus."
	icon_state = "animal"

CAPABILITIES(/obj/random/mob/mouse)
	configure(loot(
		table = list(
			/mob/living/simple_mob/animal/passive/mouse/white = 15,
			/mob/living/simple_mob/animal/passive/mouse/black = 15,
			/mob/living/simple_mob/animal/passive/mouse/brown = 30,
			/mob/living/simple_mob/animal/passive/mouse/gray = 30,
			/mob/living/simple_mob/animal/passive/mouse/rat = 30),
		chance = 85))

/obj/random/mob/fish
	name = "Random Fish"
	desc = "This is a random fish found on Sif."
	icon_state = "fish"
	mob_faction = "fish"
	overwrite_hostility = 1
	mob_hostile = 0
	mob_retaliate = 0

CAPABILITIES(/obj/random/mob/fish)
	configure(loot(
		table = list(
			/mob/living/simple_mob/animal/passive/fish/bass = 10,
			/mob/living/simple_mob/animal/passive/fish/icebass = 20,
			/mob/living/simple_mob/animal/passive/fish/trout = 20,
			/mob/living/simple_mob/animal/passive/fish/salmon = 20,
			/mob/living/simple_mob/animal/passive/fish/pike = 10,
			/mob/living/simple_mob/animal/passive/fish/perch = 10,
			/mob/living/simple_mob/animal/passive/fish/murkin = 20,
			/mob/living/simple_mob/animal/passive/fish/javelin = 15,
			/mob/living/simple_mob/animal/passive/fish/rockfish = 20,
			/mob/living/simple_mob/animal/passive/fish/solarfish = 5,
			/mob/living/simple_mob/animal/passive/crab = 10,
			/mob/living/simple_mob/animal/sif/hooligan_crab = 1)))

/obj/random/mob/bird
	name = "Random Bird"
	desc = "This is a random wild/feral bird."
	icon_state = "bird"
	mob_faction = "bird"

CAPABILITIES(/obj/random/mob/bird)
	configure(loot(
		table = list(
			/mob/living/simple_mob/animal/passive/bird/black_bird = 10,
			/mob/living/simple_mob/animal/passive/bird/azure_tit = 10,
			/mob/living/simple_mob/animal/passive/bird/european_robin = 20,
			/mob/living/simple_mob/animal/passive/bird/goldcrest = 10,
			/mob/living/simple_mob/animal/passive/bird/ringneck_dove = 20,
			/mob/living/simple_mob/animal/space/goose = 10,
			/mob/living/simple_mob/animal/passive/chicken = 5,
			/mob/living/simple_mob/animal/passive/penguin = 1)))

// Mercs
/obj/random/mob/merc
	name = "Random Mercenary"
	desc = "This is a random PoI mercenary."
	icon_state = "humanoid"

	mob_faction = FACTION_SYNDICATE
	mob_returns_home = 1
	mob_wander_distance = 7	// People like to wander, and these people probably have a lot of stuff to guard.

CAPABILITIES(/obj/random/mob/merc)
	configure(loot(
		table = list(
			/mob/living/simple_mob/humanoid/merc/melee/poi = 60,
			/mob/living/simple_mob/humanoid/merc/melee/sword/poi = 40,
			/mob/living/simple_mob/humanoid/merc/ranged/poi = 40,
			/mob/living/simple_mob/humanoid/merc/ranged/smg/poi = 30,
			/mob/living/simple_mob/humanoid/merc/ranged/laser/poi = 20,
			/mob/living/simple_mob/humanoid/merc/ranged/ionrifle/poi = 5,
			/mob/living/simple_mob/humanoid/merc/ranged/grenadier/poi = 10,
			/mob/living/simple_mob/humanoid/merc/ranged/rifle/poi = 10,
			/mob/living/simple_mob/humanoid/merc/ranged/rifle/mag/poi = 15,
			/mob/living/simple_mob/humanoid/merc/ranged/technician/poi = 10)))

/obj/random/mob/merc/armored
	name = "Random Armored Infantry Merc"
	desc = "This is a random PoI exo or robot for mercs."
	icon_state = "mecha"

CAPABILITIES(/obj/random/mob/merc/armored)
	configure(loot(
		table = list(
			/mob/living/simple_mob/mechanical/mecha/combat/gygax/dark = 30,
			/mob/living/simple_mob/mechanical/mecha/combat/gygax/medgax = 40,
			/mob/living/simple_mob/mechanical/mecha/combat/gygax = 40,
			/mob/living/simple_mob/mechanical/mecha/combat/durand/defensive/mercenary = 10,
			/mob/living/simple_mob/mechanical/mecha/hoverpod/manned = 60,
			/mob/living/simple_mob/mechanical/mecha/combat/marauder = 5,
			/mob/living/simple_mob/mechanical/mecha/combat/marauder/seraph = 1,
			/mob/living/simple_mob/mechanical/mecha/odysseus/manned = 15,
			/mob/living/simple_mob/mechanical/mecha/odysseus/murdysseus/manned = 15,
			/mob/living/simple_mob/mechanical/mecha/ripley/manned = 60)))

/obj/random/mob/merc/all
	name = "Random Mercenary All"
	desc = "A random PoI mercenary, including armored."

CAPABILITIES(/obj/random/mob/merc/all)
	configure(loot(table = list(/obj/random/mob/merc = 20, /obj/random/mob/merc/armored = 1)))

// Multiple mobs, one spawner.
/obj/random/mob/multiple
	name = "Random Multiple Mob Spawner"
	desc = "A base multiple-mob spawner. Takes lists of lists."

/obj/random/mob/multiple/sifmobs
	name = "Random Sifmob Pack"
	desc = "A pack of random neutral sif mobs."
	icon_state = "animal_group"

CAPABILITIES(/obj/random/mob/multiple/sifmobs)
	configure(loot(
		table = list(
			loot_set(60, list(/mob/living/simple_mob/animal/sif/diyaab, /mob/living/simple_mob/animal/sif/diyaab, /mob/living/simple_mob/animal/sif/diyaab)),
			loot_set(15, list(/mob/living/simple_mob/animal/sif/duck, /mob/living/simple_mob/animal/sif/duck, /mob/living/simple_mob/animal/sif/duck)),
			loot_set(15, list(/mob/living/simple_mob/animal/passive/hare, /mob/living/simple_mob/animal/passive/hare, /mob/living/simple_mob/animal/passive/hare, /mob/living/simple_mob/animal/passive/hare)),
			loot_set(10, list(/mob/living/simple_mob/animal/sif/shantak/retaliate, /mob/living/simple_mob/animal/sif/shantak/retaliate, /mob/living/simple_mob/animal/sif/shantak/retaliate, /mob/living/simple_mob/animal/sif/shantak/leader/autofollow/retaliate)),
			loot_set(5, list(/mob/living/simple_mob/animal/sif/kururak/leader, /mob/living/simple_mob/animal/sif/kururak, /mob/living/simple_mob/animal/sif/kururak)),
			loot_set(5, list(/mob/living/simple_mob/animal/sif/glitterfly, /mob/living/simple_mob/animal/sif/glitterfly, /mob/living/simple_mob/animal/sif/glitterfly, /mob/living/simple_mob/animal/sif/glitterfly, /mob/living/simple_mob/animal/sif/glitterfly)),
			loot_set(1, list(/mob/living/simple_mob/animal/goat, /mob/living/simple_mob/animal/goat)),
			loot_set(1, list(/mob/living/simple_mob/animal/sif/sakimm/intelligent, /mob/living/simple_mob/animal/sif/sakimm, /mob/living/simple_mob/animal/sif/sakimm, /mob/living/simple_mob/animal/sif/sakimm)))))

/obj/random/mob/vermin
	name = "Random Vermin"
	desc = "Often found in trash."
	icon_state = "animal"

CAPABILITIES(/obj/random/mob/vermin)
	configure(loot(
		table = list(
			/mob/living/simple_mob/animal/passive/mouse/white = 15,
			/mob/living/simple_mob/animal/passive/mouse/black = 15,
			/mob/living/simple_mob/animal/passive/mouse/brown = 30,
			/mob/living/simple_mob/animal/passive/mouse/gray = 30,
			/mob/living/simple_mob/animal/passive/mouse/rat = 30,
			/obj/effect/spider/spiderling/non_growing = 30,
			/mob/living/simple_mob/animal/passive/raccoon = 30,
			/mob/living/simple_mob/animal/passive/opossum = 30,
			/mob/living/simple_mob/animal/passive/cockroach = 40),
		chance = 85))


/obj/random/weapon // For Gateway maps and Syndicate. Can possibly spawn almost any gun in the game.
	name = "Random Illegal Weapon"
	desc = "This is a random illegal weapon."
	icon = 'icons/obj/gun.dmi'
	icon_state = "p08"
CAPABILITIES(/obj/random/weapon)
	loot(
		table = list(
			/obj/random/ammo_all = 11,
			/obj/item/gun/energy/laser = 11,
			/obj/item/gun/projectile/pirate = 11,
			/obj/item/material/twohanded/spear = 10,
			/obj/item/gun/energy/stunrevolver = 10,
			/obj/item/gun/energy/taser = 10,
			/obj/item/gun/projectile/shotgun/doublebarrel/pellet = 10,
			/obj/item/material/knife = 10,
			/obj/item/gun/projectile/luger = 10,
			/obj/item/gun/projectile/revolver/detective = 10,
			/obj/item/gun/projectile/revolver/judge = 10,
			/obj/item/gun/projectile/colt = 10,
			/obj/item/gun/projectile/shotgun/pump = 19,
			/obj/item/gun/projectile/shotgun/pump/rifle = 10,
			/obj/item/melee/baton = 10,
			/obj/item/melee/telebaton = 10,
			/obj/item/melee/classic_baton = 10,
			/obj/item/gun/projectile/automatic/wt550/lethal = 9,
			/obj/item/gun/projectile/automatic/pdw = 9,
			/obj/item/gun/projectile/automatic/sol = 9,
			/obj/item/gun/energy/crossbow/largecrossbow = 9,
			/obj/item/gun/projectile/pistol = 9,
			/obj/item/cane/concealed = 10,
			/obj/item/gun/energy/gun = 9,
			/obj/item/gun/energy/retro = 8,
			/obj/item/gun/energy/gun/eluger = 8,
			/obj/item/gun/energy/xray = 8,
			/obj/item/gun/projectile/automatic/c20r = 8,
			/obj/item/melee/energy/sword = 12,
			/obj/item/gun/projectile/derringer = 8,
			/obj/item/gun/projectile/revolver/lemat = 8,
			/obj/item/material/butterfly = 7,
			/obj/item/material/butterfly/switchblade = 7,
			/obj/item/gun/projectile/giskard = 7,
			/obj/item/gun/projectile/automatic/p90 = 7,
			/obj/item/gun/projectile/automatic/sts35 = 7,
			/obj/item/gun/projectile/shotgun/pump/combat = 7,
			/obj/item/gun/energy/sniperrifle = 6,
			/obj/item/gun/projectile/automatic/z8 = 6,
			/obj/item/gun/energy/captain = 6,
			/obj/item/material/knife/tacknife = 6,
			/obj/item/gun/projectile/shotgun/pump/USDF = 5,
			/obj/item/gun/projectile/giskard/olivaw = 5,
			/obj/item/gun/projectile/revolver/consul = 5,
			/obj/item/gun/projectile/revolver/mateba = 5,
			/obj/item/gun/projectile/revolver = 5,
			/obj/item/gun/projectile/deagle = 4,
			/obj/item/material/knife/tacknife/combatknife = 4,
			/obj/item/gun/projectile/automatic/mini_uzi = 4,
			/obj/item/gun/projectile/contender = 4,
			/obj/item/gun/projectile/contender/tacticool = 4,
			/obj/item/gun/projectile/SVD = 3,
			/obj/item/gun/energy/lasercannon = 3,
			/obj/item/gun/projectile/shotgun/pump/rifle/lever = 3,
			/obj/item/gun/projectile/automatic/bullpup = 3,
			/obj/item/gun/energy/gun/nuclear = 2,
			/obj/item/gun/projectile/automatic/l6_saw = 2,
			/obj/item/gun/energy/gun/burst = 2,
			/obj/item/storage/box/frags = 2,
			/obj/item/material/twohanded/fireaxe = 2,
			/obj/item/gun/projectile/luger/brown = 2,
			/obj/item/gun/launcher/crossbow = 2,
			/obj/item/melee/shock_maul = 2,
			/obj/item/gun/projectile/deagle/gold = 1,
			/obj/item/gun/energy/imperial = 1,
			/obj/item/gun/projectile/automatic/as24 = 1,
			/obj/item/gun/launcher/rocket = 1,
			/obj/item/gun/launcher/grenade = 1,
			/obj/item/gun/projectile/gyropistol = 1,
			/obj/item/gun/projectile/heavysniper = 1,
			/obj/item/plastique = 1,
			/obj/item/gun/energy/ionrifle = 1,
			/obj/item/material/sword = 1,
			/obj/item/material/sword/katana = 1),
		chance = 50)

/obj/random/weapon/guarenteed
CAPABILITIES(/obj/random/weapon/guarenteed)
	configure(loot(chance = 100))

/obj/random/ammo_all
	name = "Random Ammunition (All)"
	desc = "This is random ammunition. Spawns all ammo types."
	icon = 'icons/obj/ammo.dmi'
	icon_state = "666"
CAPABILITIES(/obj/random/ammo_all)
	loot(
		table = list(
			/obj/item/ammo_magazine/ammo_box/b12g = 5,
			/obj/item/ammo_magazine/ammo_box/b12g/pellet = 5,
			/obj/item/ammo_magazine/clip/c762 = 5,
			/obj/item/ammo_magazine/m380 = 5,
			/obj/item/ammo_magazine/m45 = 5,
			/obj/item/ammo_magazine/m9mm = 5,
			/obj/item/ammo_magazine/s38 = 5,
			/obj/item/ammo_magazine/clip/c45 = 4,
			/obj/item/ammo_magazine/clip/c9mm = 4,
			/obj/item/ammo_magazine/m45uzi = 4,
			/obj/item/ammo_magazine/m9mml = 4,
			/obj/item/ammo_magazine/m9mmt = 4,
			/obj/item/ammo_magazine/m9mmp90 = 4,
			/obj/item/ammo_magazine/m10mm = 4,
			/obj/item/ammo_magazine/m545/small = 4,
			/obj/item/ammo_magazine/clip/c44 = 3,
			/obj/item/ammo_magazine/ammo_box/b10mm/emp = 3,
			/obj/item/ammo_magazine/ammo_box/b10mm = 3,
			/obj/item/ammo_magazine/s44 = 3,
			/obj/item/ammo_magazine/m762 = 3,
			/obj/item/ammo_magazine/m545 = 3,
			/obj/item/cell/device/weapon = 3,
			/obj/item/ammo_magazine/m44 = 2,
			/obj/item/ammo_magazine/s357 = 2,
			/obj/item/ammo_magazine/m762/ext = 2,
			/obj/item/ammo_magazine/clip/c12g = 2,
			/obj/item/ammo_magazine/clip/c12g/pellet = 2,
			/obj/item/ammo_magazine/m45tommy = 1,
			/obj/item/ammo_casing/rocket = 1,
			/obj/item/ammo_magazine/ammo_box/b145 = 1,
			/obj/item/ammo_magazine/ammo_box/b12g/flash = 1,
			/obj/item/ammo_magazine/ammo_box/b12g/beanbag = 1,
			/obj/item/ammo_magazine/ammo_box/b12g/stunshell = 1,
			/obj/item/ammo_magazine/mtg = 1,
			/obj/item/ammo_magazine/m12gdrum = 1,
			/obj/item/ammo_magazine/m12gdrum/pellet = 1,
			/obj/item/ammo_magazine/m45tommydrum = 1))

/obj/random/cargopod
	name = "Random Cargo Item"
	desc = "Hot Stuff."
	icon = 'icons/obj/items.dmi'
	icon_state = "purplecomb"

CAPABILITIES(/obj/random/cargopod)
	loot(
		table = list(
			/obj/item/poster = 10,
			/obj/item/haircomb = 8,
			/obj/item/storage/pill_bottle/paracetamol = 6,
			/obj/item/material/butterflyblade = 6,
			/obj/item/material/butterflyhandle = 6,
			/obj/item/storage/pill_bottle/happy = 4,
			/obj/item/storage/pill_bottle/zoom = 4,
			/obj/item/material/butterfly = 4,
			/obj/item/material/butterfly/switchblade = 2,
			/obj/item/clothing/accessory/knuckledusters = 2,
			/obj/item/reagent_containers/syringe/drugs = 2,
			/obj/item/material/knife/tacknife = 1,
			/obj/item/clothing/suit/storage/vest/heavy/merc = 1,
			/obj/item/beartrap = 1,
			/obj/item/handcuffs = 1,
			/obj/item/handcuffs/legcuffs = 1,
			/obj/item/reagent_containers/syringe/steroid = 1),
		chance = 100)

//A random thing so that the spawn chance can be used w/o duplicating code.
/obj/random/trash_pile
	name = "Random Trash Pile"
	desc = "Hot Garbage."
	icon = 'icons/obj/trash_piles.dmi'
	icon_state = "randompile"
CAPABILITIES(/obj/random/trash_pile)
	loot(table = list(/obj/structure/trash_pile), chance = 100)

/obj/random/outside_mob
	name = "Random Mob"
	desc = "Eek!"
	icon = 'icons/mob/screen1.dmi'
	icon_state = "x"
	var/faction = FACTION_WILD_ANIMAL

CAPABILITIES(/obj/random/outside_mob)
	configure(map_resolver(vars = list("drop_get_turf", "faction")))
	loot(
		table = list(
			/mob/living/simple_mob/animal/passive/gaslamp = 50,
			/mob/living/simple_mob/vore/aggressive/dino/virgo3b = 20,
			/mob/living/simple_mob/vore/aggressive/dragon/virgo3b = 1),
		chance = 90,
		hook = GLOBAL_PROC_REF(loot_hook_outside_mob))


/// LOOT_HOOK for /obj/random/outside_mob: one faction for the pack, cold-tolerant, wandered off.
/proc/loot_hook_outside_mob(atom/spawned, path, list/varedits, datum/loot_rng/rng)
	var/mob/living/simple_mob/this_mob = spawned
	if(!isanimal(this_mob))
		return
	var/obj/random/outside_mob/P = path
	this_mob.faction = MAP_VAR(P, varedits, faction)
	if (this_mob.minbodytemp > 200) // Temporary hotfix. Eventually I'll add code to change all mob vars to fit the environment they are spawned in.
		this_mob.minbodytemp = 200
	//wander the mobs around so they aren't always in the same spots
	var/turf/T = null
	for(var/i = 1 to 20)
		T = get_step_rand(this_mob) || T
	if(T)
		this_mob.forceMove(T)

//Just overriding this here, no more super medkit so those can be reserved for PoIs and such
/obj/random/tetheraid
	name = "Random First Aid Kit"
	desc = "This is a random first aid kit. Does not include Combat Kits."
	icon = 'icons/obj/storage.dmi'
	icon_state = "firstaid"

CAPABILITIES(/obj/random/tetheraid)
	loot(
		table = list(
			/obj/item/storage/firstaid/regular = 10,
			/obj/item/storage/firstaid/toxin = 8,
			/obj/item/storage/firstaid/o2 = 8,
			/obj/item/storage/firstaid/adv = 5,
			/obj/item/storage/firstaid/fire = 8,
			/obj/item/denecrotizer/medical = 1))

//Override from maintenance.dm to prevent combat kits from spawning in Tether maintenance
CAPABILITIES(/obj/random/maintenance)
	loot(
		table = list(
			/obj/random/tech_supply = 300,
			/obj/random/medical = 200,
			/obj/random/tetheraid = 100,
			/obj/random/contraband = 10,
			/obj/random/action_figure = 50,
			/obj/random/plushie = 50,
			/obj/random/junk = 200,
			/obj/random/material = 200,
			/obj/random/toy = 50,
			/obj/random/tank = 100,
			/obj/random/soap = 50,
			/obj/random/drinkbottle = 60,
			/obj/random/maintenance/clean = 500))

/obj/random/action_figure/supplypack
	drop_get_turf = FALSE

/obj/random/roguemineloot
	name = "Random Rogue Mines Item"
	desc = "Hot Stuff. Hopefully"
	icon = 'icons/obj/items.dmi'
	icon_state = "spickaxe"

CAPABILITIES(/obj/random/roguemineloot)
	loot(
		table = list(
			/obj/random/mre = 5,
			/obj/random/maintenance = 5,
			/obj/random/firstaid = 4,
			/obj/random/toolbox = 3,
			/obj/random/multiple/minevault = 2,
			/obj/random/coin = 1,
			/obj/random/drinkbottle = 1,
			/obj/random/tool/alien = 1),
		chance = 100)

//Scug spawner for the picnic!
/obj/random/mob/wildscugs
	name = "Random catslug spawner"
	desc = "Spawns catslugs with random colours!"
	icon_state = "vore"
	mob_faction = "vore"
	mob_wander_distance = 4
	mob_wander = 1
	mob_returns_home = 1
	var/newname = null
	var/newdesc = null

CAPABILITIES(/obj/random/mob/wildscugs)
	configure(map_resolver(
		vars = list(
			"drop_get_turf", "overwrite_hostility", "mob_faction", "mob_returns_home",
			"mob_wander", "mob_wander_distance", "mob_hostile", "mob_ghostjoin",
			"newname", "newdesc")))
	configure(loot(chance = 75, hook = GLOBAL_PROC_REF(loot_hook_wildscugs)))


/// LOOT_HOOK for the catslug spawner: the random-mob setup, then a random colour and name.
/proc/loot_hook_wildscugs(atom/spawned, path, list/varedits, datum/loot_rng/rng)
	loot_hook_random_mob(spawned, path, varedits, rng)
	var/mob/living/simple_mob/M = spawned
	if(!istype(M))
		return
	var/obj/random/mob/wildscugs/P = path
	M.color = pick(COLOR_WHITE, COLOR_RED, COLOR_PURPLE, COLOR_YELLOW, COLOR_CYAN_BLUE, COLOR_RED_GRAY, COLOR_BEIGE, COLOR_PINK, COLOR_BLACK)
	var/newname = MAP_VAR(P, varedits, newname)
	if(newname)
		M.name = islist(newname) ? pick(newname) : newname
	var/newdesc = MAP_VAR(P, varedits, newdesc)
	if(newdesc)
		M.desc = islist(newdesc) ? pick(newdesc) : newdesc
