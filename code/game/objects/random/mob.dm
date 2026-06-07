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

/obj/random/mob/item_to_spawn()
	return pick(prob(10);/mob/living/simple_mob/animal/passive/lizard,
				prob(6);/mob/living/simple_mob/animal/sif/diyaab,
				prob(10);/mob/living/simple_mob/animal/passive/cat,
				prob(6);/mob/living/simple_mob/animal/passive/cat,
				prob(10);/mob/living/simple_mob/animal/passive/dog/corgi,
				prob(6);/mob/living/simple_mob/animal/passive/dog/corgi/puppy,
				prob(10);/mob/living/simple_mob/animal/passive/crab,
				prob(10);/mob/living/simple_mob/animal/passive/chicken,
				prob(6);/mob/living/simple_mob/animal/passive/chick,
				prob(10);/mob/living/simple_mob/animal/passive/cow,
				prob(6);/mob/living/simple_mob/animal/goat,
				prob(10);/mob/living/simple_mob/animal/passive/penguin,
				prob(10);/mob/living/simple_mob/animal/passive/mouse,
				prob(10);/mob/living/simple_mob/animal/passive/mothroach,
				prob(10);/mob/living/simple_mob/animal/passive/yithian,
				prob(10);/mob/living/simple_mob/animal/passive/tindalos,
				prob(10);/mob/living/simple_mob/animal/passive/pillbug,
				prob(10);/mob/living/simple_mob/animal/passive/dog/tamaskan,
				prob(10);/mob/living/simple_mob/animal/passive/dog/brittany,
				prob(3);/mob/living/simple_mob/animal/passive/bird/parrot,
				prob(1);/mob/living/simple_mob/animal/passive/crab)

/obj/random/mob/spawn_item() //These should only ever have simple mobs.
	var/build_path = item_to_spawn()

	var/mob/living/simple_mob/M = new build_path(src.loc)
	if(!istype(M))
		return
	if(M.has_AI())
		var/datum/ai_holder/AI = M.ai_holder
		AI.go_sleep() //Don't fight eachother while we're still setting up!
		AI.returns_home = mob_returns_home
		AI.wander = mob_wander
		AI.max_home_distance = mob_wander_distance
		if(overwrite_hostility)
			AI.hostile = mob_hostile
			AI.retaliate = mob_retaliate
		AI.go_wake() //Now you can kill eachother if your faction didn't override.

	if(pixel_x || pixel_y)
		M.pixel_x = pixel_x
		M.pixel_y = pixel_y

	if(mob_faction)
		M.faction = mob_faction

	if(mob_ghostjoin)
		if(prob(mob_ghostjoin))
			M.ghostjoin = 1

/obj/random/mob/sif
	name = "Random Sif Animal"
	desc = "This is a random cold weather animal."
	icon_state = "animal"

	mob_returns_home = 1
	mob_wander_distance = 10

/obj/random/mob/sif/item_to_spawn()
	return pick(prob(30);/mob/living/simple_mob/animal/sif/diyaab,
				prob(20);/mob/living/simple_mob/animal/passive/hare,
				prob(15);/mob/living/simple_mob/animal/passive/crab,
				prob(15);/mob/living/simple_mob/animal/passive/penguin,
				prob(15);/mob/living/simple_mob/animal/passive/mouse,
				prob(15);/mob/living/simple_mob/animal/passive/dog/tamaskan,
				prob(10);/mob/living/simple_mob/animal/sif/siffet,
				prob(2);/mob/living/simple_mob/animal/giant_spider/frost,
				prob(1);/mob/living/simple_mob/animal/space/goose,
				prob(20);/mob/living/simple_mob/animal/passive/crab)


/obj/random/mob/sif/peaceful
	name = "Random Peaceful Sif Animal"
	desc = "This is a random peaceful cold weather animal."
	icon_state = "animal_passive"

	mob_returns_home = 1
	mob_wander_distance = 12

/obj/random/mob/sif/peaceful/item_to_spawn()
	return pick(prob(30);/mob/living/simple_mob/animal/sif/diyaab,
				prob(20);/mob/living/simple_mob/animal/passive/hare,
				prob(15);/mob/living/simple_mob/animal/passive/crab,
				prob(15);/mob/living/simple_mob/animal/passive/penguin,
				prob(15);/mob/living/simple_mob/animal/passive/mouse,
				prob(15);/mob/living/simple_mob/animal/passive/dog/tamaskan,
				prob(20);/mob/living/simple_mob/animal/sif/hooligan_crab)

/obj/random/mob/sif/hostile
	name = "Random Hostile Sif Animal"
	desc = "This is a random hostile cold weather animal."
	icon_state = "animal_hostile"

/obj/random/mob/sif/hostile/item_to_spawn()
	return pick(prob(22);/mob/living/simple_mob/animal/sif/savik,
				prob(33);/mob/living/simple_mob/animal/giant_spider/frost,
				prob(20);/mob/living/simple_mob/animal/sif/frostfly,
				prob(10);/mob/living/simple_mob/animal/sif/tymisian,
				prob(45);/mob/living/simple_mob/animal/sif/shantak)

/obj/random/mob/sif/kururak
	name = "Random Kururak"
	desc = "This is a random kururak, either waking or hibernating. Will be hostile if more than one are waking."
	icon_state = "frost"

/obj/random/mob/sif/kururak/item_to_spawn()
	return pick(prob(1);/mob/living/simple_mob/animal/sif/kururak/hibernate,
				prob(20);/mob/living/simple_mob/animal/sif/kururak)

/obj/random/mob/spider
	name = "Random Spider" //Spiders should patrol where they spawn.
	desc = "This is a random boring spider."
	icon_state = "guard"

	mob_returns_home = 1
	mob_wander_distance = 4

/obj/random/mob/spider/item_to_spawn()
	return pick(prob(33);/mob/living/simple_mob/animal/giant_spider/hunter,
				prob(45);/mob/living/simple_mob/animal/giant_spider)

/obj/random/mob/spider/nurse
	name = "Random Nurse Spider"
	desc = "This is a random nurse spider."
	icon_state = "nurse"

	mob_returns_home = 1
	mob_wander_distance = 4

/obj/random/mob/spider/nurse/item_to_spawn()
	return pick(prob(22);/mob/living/simple_mob/animal/giant_spider/nurse/hat,
				prob(45);/mob/living/simple_mob/animal/giant_spider/nurse)

/obj/random/mob/spider/mutant
	name = "Random Mutant Spider"
	desc = "This is a random mutated spider."
	icon_state = "phoron"

/obj/random/mob/spider/mutant/item_to_spawn()
	return pick(prob(5);/obj/random/mob/spider,
				prob(10);/mob/living/simple_mob/animal/giant_spider/webslinger,
				prob(10);/mob/living/simple_mob/animal/giant_spider/carrier,
				prob(33);/mob/living/simple_mob/animal/giant_spider/lurker,
				prob(33);/mob/living/simple_mob/animal/giant_spider/tunneler,
				prob(40);/mob/living/simple_mob/animal/giant_spider/pepper,
				prob(20);/mob/living/simple_mob/animal/giant_spider/thermic,
				prob(40);/mob/living/simple_mob/animal/giant_spider/electric,
				prob(1);/mob/living/simple_mob/animal/giant_spider/phorogenic,
				prob(40);/mob/living/simple_mob/animal/giant_spider/frost)

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

/obj/random/mob/robotic/item_to_spawn() //Hivebots have a total number of 'lots' equal to the lesser drone, at 60.
	return pick(prob(60);/mob/living/simple_mob/mechanical/combat_drone/lesser,
				prob(50);/mob/living/simple_mob/mechanical/combat_drone,
				prob(50);/mob/living/simple_mob/mechanical/mining_drone,
				prob(15);/mob/living/simple_mob/mechanical/mecha/ripley,
				prob(15);/mob/living/simple_mob/mechanical/mecha/odysseus,
				prob(10);/mob/living/simple_mob/mechanical/hivebot,
				prob(15);/mob/living/simple_mob/mechanical/hivebot/swarm,
				prob(10);/mob/living/simple_mob/mechanical/hivebot/ranged_damage,
				prob(5);/mob/living/simple_mob/mechanical/hivebot/ranged_damage/rapid,
				prob(5);/mob/living/simple_mob/mechanical/hivebot/ranged_damage/ion,
				prob(5);/mob/living/simple_mob/mechanical/hivebot/ranged_damage/laser,
				prob(5);/mob/living/simple_mob/mechanical/hivebot/ranged_damage/strong,
				prob(5);/mob/living/simple_mob/mechanical/hivebot/ranged_damage/strong/guard)

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

/obj/random/mob/robotic/drone/item_to_spawn()
	return pick(prob(6);/mob/living/simple_mob/mechanical/combat_drone/lesser,
				prob(1);/mob/living/simple_mob/mechanical/combat_drone,
				prob(3);/mob/living/simple_mob/mechanical/mining_drone)

/obj/random/mob/robotic/hivebot
	name = "Random Hivebot"
	desc = "This is a random hivebot."
	icon_state = "robot"

	mob_faction = FACTION_HIVEBOT

/obj/random/mob/robotic/hivebot/item_to_spawn()
	return pick(prob(10);/mob/living/simple_mob/mechanical/hivebot,
				prob(15);/mob/living/simple_mob/mechanical/hivebot/swarm,
				prob(10);/mob/living/simple_mob/mechanical/hivebot/ranged_damage,
				prob(5);/mob/living/simple_mob/mechanical/hivebot/ranged_damage/rapid,
				prob(5);/mob/living/simple_mob/mechanical/hivebot/ranged_damage/ion,
				prob(5);/mob/living/simple_mob/mechanical/hivebot/ranged_damage/laser,
				prob(5);/mob/living/simple_mob/mechanical/hivebot/ranged_damage/strong,
				prob(5);/mob/living/simple_mob/mechanical/hivebot/ranged_damage/strong/guard)

//Mice

/obj/random/mob/mouse
	name = "Random Mouse"
	desc = "This is a random boring maus."
	icon_state = "animal"
	spawn_nothing_percentage = 15

/obj/random/mob/mouse/item_to_spawn()
	return pick(prob(15);/mob/living/simple_mob/animal/passive/mouse/white,
				prob(15);/mob/living/simple_mob/animal/passive/mouse/black,
				prob(30);/mob/living/simple_mob/animal/passive/mouse/brown,
				prob(30);/mob/living/simple_mob/animal/passive/mouse/gray,
				prob(30);/mob/living/simple_mob/animal/passive/mouse/rat)

/obj/random/mob/fish
	name = "Random Fish"
	desc = "This is a random fish found on Sif."
	icon_state = "fish"
	mob_faction = "fish"
	overwrite_hostility = 1
	mob_hostile = 0
	mob_retaliate = 0

/obj/random/mob/fish/item_to_spawn()
	return pick(prob(10);/mob/living/simple_mob/animal/passive/fish/bass,
				prob(20);/mob/living/simple_mob/animal/passive/fish/icebass,
				prob(20);/mob/living/simple_mob/animal/passive/fish/trout,
				prob(20);/mob/living/simple_mob/animal/passive/fish/salmon,
				prob(10);/mob/living/simple_mob/animal/passive/fish/pike,
				prob(10);/mob/living/simple_mob/animal/passive/fish/perch,
				prob(20);/mob/living/simple_mob/animal/passive/fish/murkin,
				prob(15);/mob/living/simple_mob/animal/passive/fish/javelin,
				prob(20);/mob/living/simple_mob/animal/passive/fish/rockfish,
				prob(5);/mob/living/simple_mob/animal/passive/fish/solarfish,
				prob(10);/mob/living/simple_mob/animal/passive/crab,
				prob(1);/mob/living/simple_mob/animal/sif/hooligan_crab)

/obj/random/mob/bird
	name = "Random Bird"
	desc = "This is a random wild/feral bird."
	icon_state = "bird"
	mob_faction = "bird"

/obj/random/mob/bird/item_to_spawn()
	return pick(prob(10);/mob/living/simple_mob/animal/passive/bird/black_bird,
				prob(10);/mob/living/simple_mob/animal/passive/bird/azure_tit,
				prob(20);/mob/living/simple_mob/animal/passive/bird/european_robin,
				prob(10);/mob/living/simple_mob/animal/passive/bird/goldcrest,
				prob(20);/mob/living/simple_mob/animal/passive/bird/ringneck_dove,
				prob(10);/mob/living/simple_mob/animal/space/goose,
				prob(5);/mob/living/simple_mob/animal/passive/chicken,
				prob(1);/mob/living/simple_mob/animal/passive/penguin)

// Mercs
/obj/random/mob/merc
	name = "Random Mercenary"
	desc = "This is a random PoI mercenary."
	icon_state = "humanoid"

	mob_faction = FACTION_SYNDICATE
	mob_returns_home = 1
	mob_wander_distance = 7	// People like to wander, and these people probably have a lot of stuff to guard.

/obj/random/mob/merc/item_to_spawn()
	return pick(prob(60);/mob/living/simple_mob/humanoid/merc/melee/poi,
				prob(40);/mob/living/simple_mob/humanoid/merc/melee/sword/poi,
				prob(40);/mob/living/simple_mob/humanoid/merc/ranged/poi,
				prob(30);/mob/living/simple_mob/humanoid/merc/ranged/smg/poi,
				prob(20);/mob/living/simple_mob/humanoid/merc/ranged/laser/poi,
				prob(5);/mob/living/simple_mob/humanoid/merc/ranged/ionrifle/poi,
				prob(10);/mob/living/simple_mob/humanoid/merc/ranged/grenadier/poi,
				prob(10);/mob/living/simple_mob/humanoid/merc/ranged/rifle/poi,
				prob(15);/mob/living/simple_mob/humanoid/merc/ranged/rifle/mag/poi,
				prob(10);/mob/living/simple_mob/humanoid/merc/ranged/technician/poi
				)

/obj/random/mob/merc/armored
	name = "Random Armored Infantry Merc"
	desc = "This is a random PoI exo or robot for mercs."
	icon_state = "mecha"

/obj/random/mob/merc/armored/item_to_spawn()
	return pick(prob(30);/mob/living/simple_mob/mechanical/mecha/combat/gygax/dark,
				prob(40);/mob/living/simple_mob/mechanical/mecha/combat/gygax/medgax,
				prob(40);/mob/living/simple_mob/mechanical/mecha/combat/gygax,
				prob(10);/mob/living/simple_mob/mechanical/mecha/combat/durand/defensive/mercenary,
				prob(60);/mob/living/simple_mob/mechanical/mecha/hoverpod/manned,
				prob(5);/mob/living/simple_mob/mechanical/mecha/combat/marauder,
				prob(1);/mob/living/simple_mob/mechanical/mecha/combat/marauder/seraph,
				prob(15);/mob/living/simple_mob/mechanical/mecha/odysseus/manned,
				prob(15);/mob/living/simple_mob/mechanical/mecha/odysseus/murdysseus/manned,
				prob(60);/mob/living/simple_mob/mechanical/mecha/ripley/manned
				)

/obj/random/mob/merc/all
	name = "Random Mercenary All"
	desc = "A random PoI mercenary, including armored."

/obj/random/mob/merc/all/item_to_spawn()
	return pick(prob(20);/obj/random/mob/merc,
				prob(1);/obj/random/mob/merc/armored
				)

// Multiple mobs, one spawner.
/obj/random/mob/multiple
	name = "Random Multiple Mob Spawner"
	desc = "A base multiple-mob spawner. Takes lists of lists."

/obj/random/mob/multiple/spawn_item()
	var/list/things_to_make = item_to_spawn()

	for(var/new_type in things_to_make)

		var/mob/living/simple_mob/M = new new_type(src.loc)

		if(!istype(M))
			continue

		if(M.has_AI())
			var/datum/ai_holder/AI = M.ai_holder
			AI.go_sleep() //Don't fight eachother while we're still setting up!
			AI.returns_home = mob_returns_home
			AI.wander = mob_wander
			AI.max_home_distance = mob_wander_distance
			if(overwrite_hostility)
				AI.hostile = mob_hostile
				AI.retaliate = mob_retaliate
			AI.go_wake() //Now you can kill eachother if your faction didn't override.

		if(pixel_x || pixel_y)
			M.pixel_x = pixel_x
			M.pixel_y = pixel_y

/obj/random/mob/multiple/sifmobs
	name = "Random Sifmob Pack"
	desc = "A pack of random neutral sif mobs."
	icon_state = "animal_group"

/obj/random/mob/multiple/sifmobs/item_to_spawn()
	return pick(
			prob(60);list(
				/mob/living/simple_mob/animal/sif/diyaab,
				/mob/living/simple_mob/animal/sif/diyaab,
				/mob/living/simple_mob/animal/sif/diyaab
			),
			prob(15);list(
				/mob/living/simple_mob/animal/sif/duck,
				/mob/living/simple_mob/animal/sif/duck,
				/mob/living/simple_mob/animal/sif/duck
			),
			prob(15);list(
				/mob/living/simple_mob/animal/passive/hare,
				/mob/living/simple_mob/animal/passive/hare,
				/mob/living/simple_mob/animal/passive/hare,
				/mob/living/simple_mob/animal/passive/hare
			),
			prob(10);list(
				/mob/living/simple_mob/animal/sif/shantak/retaliate,
				/mob/living/simple_mob/animal/sif/shantak/retaliate,
				/mob/living/simple_mob/animal/sif/shantak/retaliate,
				/mob/living/simple_mob/animal/sif/shantak/leader/autofollow/retaliate
			),
			prob(5);list(
				/mob/living/simple_mob/animal/sif/kururak/leader,
				/mob/living/simple_mob/animal/sif/kururak,
				/mob/living/simple_mob/animal/sif/kururak
			),
			prob(5);list(
				/mob/living/simple_mob/animal/sif/glitterfly,
				/mob/living/simple_mob/animal/sif/glitterfly,
				/mob/living/simple_mob/animal/sif/glitterfly,
				/mob/living/simple_mob/animal/sif/glitterfly,
				/mob/living/simple_mob/animal/sif/glitterfly
			),
			prob(1);list(
				/mob/living/simple_mob/animal/goat,
				/mob/living/simple_mob/animal/goat
			),
			prob(1);list(
				/mob/living/simple_mob/animal/sif/sakimm/intelligent,
				/mob/living/simple_mob/animal/sif/sakimm,
				/mob/living/simple_mob/animal/sif/sakimm,
				/mob/living/simple_mob/animal/sif/sakimm
			)
		)

/obj/random/mob/vermin
	name = "Random Vermin"
	desc = "Often found in trash."
	icon_state = "animal"
	spawn_nothing_percentage = 15

/obj/random/mob/vermin/item_to_spawn()
	return pick(prob(15);/mob/living/simple_mob/animal/passive/mouse/white,
				prob(15);/mob/living/simple_mob/animal/passive/mouse/black,
				prob(30);/mob/living/simple_mob/animal/passive/mouse/brown,
				prob(30);/mob/living/simple_mob/animal/passive/mouse/gray,
				prob(30);/mob/living/simple_mob/animal/passive/mouse/rat,
				prob(30);/obj/effect/spider/spiderling/non_growing,
				prob(30);/mob/living/simple_mob/animal/passive/raccoon,
				prob(30);/mob/living/simple_mob/animal/passive/opossum,
				prob(40);/mob/living/simple_mob/animal/passive/cockroach,
				)


// === merged from mob_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/random/weapon // For Gateway maps and Syndicate. Can possibly spawn almost any gun in the game.
	name = "Random Illegal Weapon"
	desc = "This is a random illegal weapon."
	icon = 'icons/obj/gun.dmi'
	icon_state = "p08"
	spawn_nothing_percentage = 50
/obj/random/weapon/item_to_spawn()
	return pick(prob(11);/obj/random/ammo_all,\
				prob(11);/obj/item/gun/energy/laser,\
				prob(11);/obj/item/gun/projectile/pirate,\
				prob(10);/obj/item/material/twohanded/spear,\
				prob(10);/obj/item/gun/energy/stunrevolver,\
				prob(10);/obj/item/gun/energy/taser,\
				prob(10);/obj/item/gun/projectile/shotgun/doublebarrel/pellet,\
				prob(10);/obj/item/material/knife,\
				prob(10);/obj/item/gun/projectile/luger,\
			/*	prob(10);/obj/item/gun/projectile/pipegun,\ */
				prob(10);/obj/item/gun/projectile/revolver/detective,\
				prob(10);/obj/item/gun/projectile/revolver/judge,\
				prob(10);/obj/item/gun/projectile/colt,\
				prob(10);/obj/item/gun/projectile/shotgun/pump,\
				prob(10);/obj/item/gun/projectile/shotgun/pump/rifle,\
				prob(10);/obj/item/melee/baton,\
				prob(10);/obj/item/melee/telebaton,\
				prob(10);/obj/item/melee/classic_baton,\
				prob(9);/obj/item/gun/projectile/automatic/wt550/lethal,\
				prob(9);/obj/item/gun/projectile/automatic/pdw,\
				prob(9);/obj/item/gun/projectile/automatic/sol, \
				prob(9);/obj/item/gun/energy/crossbow/largecrossbow,\
				prob(9);/obj/item/gun/projectile/pistol,\
				prob(9);/obj/item/gun/projectile/shotgun/pump,\
				prob(9);/obj/item/cane/concealed,\
				prob(9);/obj/item/gun/energy/gun,\
				prob(8);/obj/item/gun/energy/retro,\
				prob(8);/obj/item/gun/energy/gun/eluger,\
				prob(8);/obj/item/gun/energy/xray,\
				prob(8);/obj/item/gun/projectile/automatic/c20r,\
				prob(8);/obj/item/melee/energy/sword,\
				prob(8);/obj/item/gun/projectile/derringer,\
				prob(8);/obj/item/gun/projectile/revolver/lemat,\
			/*	prob(8);/obj/item/gun/projectile/shotgun/pump/rifle/mosin,\ */
			/*	prob(8);/obj/item/gun/projectile/automatic/m41a,\ */
				prob(7);/obj/item/material/butterfly,\
				prob(7);/obj/item/material/butterfly/switchblade,\
				prob(7);/obj/item/gun/projectile/giskard,\
				prob(7);/obj/item/gun/projectile/automatic/p90,\
				prob(7);/obj/item/gun/projectile/automatic/sts35,\
				prob(7);/obj/item/gun/projectile/shotgun/pump/combat,\
				prob(6);/obj/item/gun/energy/sniperrifle,\
				prob(6);/obj/item/gun/projectile/automatic/z8,\
				prob(6);/obj/item/gun/energy/captain,\
				prob(6);/obj/item/material/knife/tacknife,\
				prob(5);/obj/item/gun/projectile/shotgun/pump/USDF,\
				prob(5);/obj/item/gun/projectile/giskard/olivaw,\
				prob(5);/obj/item/gun/projectile/revolver/consul,\
				prob(5);/obj/item/gun/projectile/revolver/mateba,\
				prob(5);/obj/item/gun/projectile/revolver,\
				prob(4);/obj/item/gun/projectile/deagle,\
				prob(4);/obj/item/material/knife/tacknife/combatknife,\
				prob(4);/obj/item/melee/energy/sword,\
				prob(4);/obj/item/gun/projectile/automatic/mini_uzi,\
				prob(4);/obj/item/gun/projectile/contender,\
				prob(4);/obj/item/gun/projectile/contender/tacticool,\
				prob(3);/obj/item/gun/projectile/SVD,\
				prob(3);/obj/item/gun/energy/lasercannon,\
				prob(3);/obj/item/gun/projectile/shotgun/pump/rifle/lever,\
				prob(3);/obj/item/gun/projectile/automatic/bullpup,\
				/*prob(2);/obj/item/gun/energy/pulse_rifle,\ */ //CHOMPEDIT Players should absolutely not have this
				prob(2);/obj/item/gun/energy/gun/nuclear,\
				prob(2);/obj/item/gun/projectile/automatic/l6_saw,\
				prob(2);/obj/item/gun/energy/gun/burst,\
				prob(2);/obj/item/storage/box/frags,\
				prob(2);/obj/item/material/twohanded/fireaxe,\
				prob(2);/obj/item/gun/projectile/luger/brown,\
				prob(2);/obj/item/gun/launcher/crossbow,\
				prob(2);/obj/item/melee/shock_maul,\
			/*	prob(1);/obj/item/gun/projectile/automatic/battlerifle,\ */ // Too OP
				prob(1);/obj/item/gun/projectile/deagle/gold,\
				prob(1);/obj/item/gun/energy/imperial,\
				prob(1);/obj/item/gun/projectile/automatic/as24,\
				prob(1);/obj/item/gun/launcher/rocket,\
				prob(1);/obj/item/gun/launcher/grenade,\
				prob(1);/obj/item/gun/projectile/gyropistol,\
				prob(1);/obj/item/gun/projectile/heavysniper,\
				prob(1);/obj/item/plastique,\
				prob(1);/obj/item/gun/energy/ionrifle,\
				prob(1);/obj/item/material/sword,\
				prob(1);/obj/item/cane/concealed,\
				prob(1);/obj/item/material/sword/katana)

/obj/random/weapon/guarenteed
	spawn_nothing_percentage = 0

/obj/random/ammo_all
	name = "Random Ammunition (All)"
	desc = "This is random ammunition. Spawns all ammo types."
	icon = 'icons/obj/ammo.dmi'
	icon_state = "666"
/obj/random/ammo_all/item_to_spawn()
	return pick(prob(5);/obj/item/ammo_magazine/ammo_box/b12g,\
				prob(5);/obj/item/ammo_magazine/ammo_box/b12g/pellet,\
				prob(5);/obj/item/ammo_magazine/clip/c762,\
				prob(5);/obj/item/ammo_magazine/m380,\
				prob(5);/obj/item/ammo_magazine/m45,\
				prob(5);/obj/item/ammo_magazine/m9mm,\
				prob(5);/obj/item/ammo_magazine/s38,\
				prob(4);/obj/item/ammo_magazine/clip/c45,\
				prob(4);/obj/item/ammo_magazine/clip/c9mm,\
				prob(4);/obj/item/ammo_magazine/m45uzi,\
				prob(4);/obj/item/ammo_magazine/m9mml,\
				prob(4);/obj/item/ammo_magazine/m9mmt,\
				prob(4);/obj/item/ammo_magazine/m9mmp90,\
				prob(4);/obj/item/ammo_magazine/m10mm,\
				prob(4);/obj/item/ammo_magazine/m545/small,\
				prob(3);/obj/item/ammo_magazine/clip/c44,\
				prob(3);/obj/item/ammo_magazine/ammo_box/b10mm/emp,\
				prob(3);/obj/item/ammo_magazine/ammo_box/b10mm,\
				prob(3);/obj/item/ammo_magazine/s44,\
				prob(3);/obj/item/ammo_magazine/m762,\
				prob(3);/obj/item/ammo_magazine/m545,\
				prob(3);/obj/item/cell/device/weapon,\
				prob(2);/obj/item/ammo_magazine/m44,\
				prob(2);/obj/item/ammo_magazine/s357,\
				prob(2);/obj/item/ammo_magazine/m762/ext,\
				prob(2);/obj/item/ammo_magazine/clip/c12g,
				prob(2);/obj/item/ammo_magazine/clip/c12g/pellet,
				prob(1);/obj/item/ammo_magazine/m45tommy,
			/*	prob(1);/obj/item/ammo_magazine/m95, */
				prob(1);/obj/item/ammo_casing/rocket,
				prob(1);/obj/item/ammo_magazine/ammo_box/b145,
				prob(1);/obj/item/ammo_magazine/ammo_box/b12g/flash,
				prob(1);/obj/item/ammo_magazine/ammo_box/b12g/beanbag,
				prob(1);/obj/item/ammo_magazine/ammo_box/b12g/stunshell,
				prob(1);/obj/item/ammo_magazine/mtg,
				prob(1);/obj/item/ammo_magazine/m12gdrum,
				prob(1);/obj/item/ammo_magazine/m12gdrum/pellet,
				prob(1);/obj/item/ammo_magazine/m45tommydrum
				)

/obj/random/cargopod
	name = "Random Cargo Item"
	desc = "Hot Stuff."
	icon = 'icons/obj/items.dmi'
	icon_state = "purplecomb"
	spawn_nothing_percentage = 0

/obj/random/cargopod/item_to_spawn()
	return pick(prob(10);/obj/item/poster,
				prob(8);/obj/item/haircomb,
				prob(6);/obj/item/storage/pill_bottle/paracetamol,
				prob(6);/obj/item/material/butterflyblade,
				prob(6);/obj/item/material/butterflyhandle,
				prob(4);/obj/item/storage/pill_bottle/happy,
				prob(4);/obj/item/storage/pill_bottle/zoom,
				prob(4);/obj/item/material/butterfly,
				prob(2);/obj/item/material/butterfly/switchblade,
				prob(2);/obj/item/clothing/accessory/knuckledusters,
				prob(2);/obj/item/reagent_containers/syringe/drugs,
				prob(1);/obj/item/material/knife/tacknife,
				prob(1);/obj/item/clothing/suit/storage/vest/heavy/merc,
				prob(1);/obj/item/beartrap,
				prob(1);/obj/item/handcuffs,
				prob(1);/obj/item/handcuffs/legcuffs,
				prob(1);/obj/item/reagent_containers/syringe/steroid)

//A random thing so that the spawn_nothing_percentage can be used w/o duplicating code.
/obj/random/trash_pile
	name = "Random Trash Pile"
	desc = "Hot Garbage."
	icon = 'icons/obj/trash_piles.dmi'
	icon_state = "randompile"
	spawn_nothing_percentage = 0
/obj/random/trash_pile/item_to_spawn()
	return	/obj/structure/trash_pile

/obj/random/outside_mob
	name = "Random Mob"
	desc = "Eek!"
	icon = 'icons/mob/screen1.dmi'
	icon_state = "x"
	spawn_nothing_percentage = 10
	var/faction = FACTION_WILD_ANIMAL

/obj/random/outside_mob/item_to_spawn() // Special version for mobs to have the same faction.
	return pick(
				prob(50);/mob/living/simple_mob/animal/passive/gaslamp,
//				prob(50);/mob/living/simple_mob/vore/otie/feral, // Removed until Otie code is unfucked.
				prob(20);/mob/living/simple_mob/vore/aggressive/dino/virgo3b,
				prob(1);/mob/living/simple_mob/vore/aggressive/dragon/virgo3b)

/obj/random/outside_mob/spawn_item()
	. = ..()
	if(isanimal(.))
		var/mob/living/simple_mob/this_mob = .
		this_mob.faction = src.faction
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

/obj/random/tetheraid/item_to_spawn()
	return pick(prob(10);/obj/item/storage/firstaid/regular,
				prob(8);/obj/item/storage/firstaid/toxin,
				prob(8);/obj/item/storage/firstaid/o2,
				prob(5);/obj/item/storage/firstaid/adv,
				prob(8);/obj/item/storage/firstaid/fire,
				prob(1);/obj/item/denecrotizer/medical)

//Override from maintenance.dm to prevent combat kits from spawning in Tether maintenance
/obj/random/maintenance/item_to_spawn()
	return pick(prob(300);/obj/random/tech_supply,
				prob(200);/obj/random/medical,
				prob(100);/obj/random/tetheraid,
				prob(10);/obj/random/contraband,
				prob(50);/obj/random/action_figure,
				prob(50);/obj/random/plushie,
				prob(200);/obj/random/junk,
				prob(200);/obj/random/material,
				prob(50);/obj/random/toy,
				prob(100);/obj/random/tank,
				prob(50);/obj/random/soap,
				prob(60);/obj/random/drinkbottle,
				prob(500);/obj/random/maintenance/clean)

/obj/random/action_figure/supplypack
	drop_get_turf = FALSE

/obj/random/roguemineloot
	name = "Random Rogue Mines Item"
	desc = "Hot Stuff. Hopefully"
	icon = 'icons/obj/items.dmi'
	icon_state = "spickaxe"
	spawn_nothing_percentage = 0

/obj/random/roguemineloot/item_to_spawn()
	return pick(prob(5);/obj/random/mre,
				prob(5);/obj/random/maintenance,
				prob(4);/obj/random/firstaid,
				prob(3);/obj/random/toolbox,
				prob(2);/obj/random/multiple/minevault,
				prob(1);/obj/random/coin,
				prob(1);/obj/random/drinkbottle,
				prob(1);/obj/random/tool/alien)

//Scug spawner for the picnic!
/obj/random/mob/wildscugs
	name = "Random catslug spawner"
	desc = "Spawns catslugs with random colours!"
	icon_state = "vore"
	mob_faction = "vore"
	spawn_nothing_percentage = 25
	mob_wander_distance = 4
	mob_wander = 1
	mob_returns_home = 1
	var/newname = null
	var/newdesc = null

/*//CHOMP Remove Among Us meme
/obj/random/mob/wildscugs/item_to_spawn()
	return pick(prob(99); /mob/living/simple_mob/vore/alienanimals/catslug,
				prob(1); /mob/living/simple_mob/vore/alienanimals/catslug/suslug/color) //A super rare surprise
*/ //CHOMP Remove end
/obj/random/mob/wildscugs/spawn_item()
	var/build_path = item_to_spawn()

	var/mob/living/simple_mob/M = new build_path(src.loc)
	if(!istype(M))
		return
	if(M.has_AI())
		var/datum/ai_holder/AI = M.ai_holder
		AI.go_sleep() //Don't fight eachother while we're still setting up!
		AI.returns_home = mob_returns_home
		AI.wander = mob_wander
		AI.max_home_distance = mob_wander_distance
		if(overwrite_hostility)
			AI.hostile = mob_hostile
			AI.retaliate = mob_retaliate
		AI.go_wake() //Now you can kill eachother if your faction didn't override.

	if(pixel_x || pixel_y)
		M.pixel_x = pixel_x
		M.pixel_y = pixel_y

	if(mob_faction)
		M.faction = mob_faction

	M.color = pick(COLOR_WHITE, COLOR_RED, COLOR_PURPLE, COLOR_YELLOW, COLOR_CYAN_BLUE, COLOR_RED_GRAY, COLOR_BEIGE, COLOR_PINK, COLOR_BLACK)
	if(newname)
		if(islist(newname))
			M.name = pick(newname)
		else
			M.name = newname
	if(newdesc)
		if(islist(newdesc))
			M.desc = pick(newdesc)
		else
			M.desc = newdesc
