/obj/random/mob/semirandom_mob_spawner
	name = "Semi-Random Spawner"
	desc = "Spawns groups of mobs that are all of the same theme type/theme."
	icon = 'icons/mob/randomlandmarks.dmi'
	icon_state = "monster"
	mob_returns_home = 1
	mob_wander_distance = 7

CAPABILITIES(/obj/random/mob/semirandom_mob_spawner)
	configure(loot(
		per_round = TRUE,
		table = list(
			loot_sub(1, list(/mob/living/simple_mob/animal/goat)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/bird, /mob/living/simple_mob/animal/passive/bird/azure_tit, /mob/living/simple_mob/animal/passive/bird/black_bird, /mob/living/simple_mob/animal/passive/bird/european_robin, /mob/living/simple_mob/animal/passive/bird/goldcrest, /mob/living/simple_mob/animal/passive/bird/ringneck_dove, /mob/living/simple_mob/animal/passive/bird/parrot, /mob/living/simple_mob/animal/passive/bird/parrot/black_headed_caique, /mob/living/simple_mob/animal/passive/bird/parrot/budgerigar, /mob/living/simple_mob/animal/passive/bird/parrot/budgerigar/blue, /mob/living/simple_mob/animal/passive/bird/parrot/budgerigar/bluegreen, /mob/living/simple_mob/animal/passive/bird/parrot/cockatiel, /mob/living/simple_mob/animal/passive/bird/parrot/cockatiel/grey, /mob/living/simple_mob/animal/passive/bird/parrot/cockatiel/white, /mob/living/simple_mob/animal/passive/bird/parrot/cockatiel/yellowish, /mob/living/simple_mob/animal/passive/bird/parrot/eclectus, /mob/living/simple_mob/animal/passive/bird/parrot/grey_parrot, /mob/living/simple_mob/animal/passive/bird/parrot/kea, /mob/living/simple_mob/animal/passive/bird/parrot/pink_cockatoo, /mob/living/simple_mob/animal/passive/bird/parrot/sulphur_cockatoo, /mob/living/simple_mob/animal/passive/bird/parrot/white_caique, /mob/living/simple_mob/animal/passive/bird/parrot/white_cockatoo)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/cat, /mob/living/simple_mob/animal/passive/cat/black)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/chick)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/cow)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/dog/brittany)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/dog/corgi)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/dog/tamaskan)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/fox)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/hare)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/lizard)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/mouse)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/mouse/jerboa)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/mothroach)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/opossum)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/pillbug)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/snake)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/snake/red)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/snake/python)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/tindalos)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/yithian)),
			loot_sub(1, list(/mob/living/simple_mob/vore/wolf = 10, /mob/living/simple_mob/vore/wolf/direwolf = 5, /mob/living/simple_mob/vore/greatwolf = 1, /mob/living/simple_mob/vore/greatwolf/black = 1, /mob/living/simple_mob/vore/greatwolf/grey = 1)),
			loot_sub(1, list(/mob/living/simple_mob/vore/rabbit)),
			loot_sub(1, list(/mob/living/simple_mob/vore/redpanda)),
			loot_sub(1, list(/mob/living/simple_mob/vore/woof)),
			loot_sub(1, list(/mob/living/simple_mob/vore/fennec)),
			loot_sub(1, list(/mob/living/simple_mob/vore/fennix)),
			loot_sub(1, list(/mob/living/simple_mob/vore/hippo)),
			loot_sub(1, list(/mob/living/simple_mob/vore/horse)),
			loot_sub(1, list(/mob/living/simple_mob/vore/bee)),
			loot_sub(1, list(/mob/living/simple_mob/animal/space/bear, /mob/living/simple_mob/animal/space/bear/brown)),
			loot_sub(1, list(/mob/living/simple_mob/vore/otie/feral, /mob/living/simple_mob/vore/otie/feral/chubby, /mob/living/simple_mob/vore/otie/red, /mob/living/simple_mob/vore/otie/red/chubby)),
			loot_sub(1, list(/mob/living/simple_mob/animal/sif/diyaab)),
			loot_sub(1, list(/mob/living/simple_mob/animal/sif/duck)),
			loot_sub(1, list(/mob/living/simple_mob/animal/sif/frostfly)),
			loot_sub(1, list(/mob/living/simple_mob/animal/sif/glitterfly = 50, /mob/living/simple_mob/animal/sif/glitterfly/rare = 1)),
			loot_sub(1, list(/mob/living/simple_mob/animal/sif/kururak = 10, /mob/living/simple_mob/animal/sif/kururak/leader = 1, /mob/living/simple_mob/animal/sif/kururak/hibernate = 2)),
			loot_sub(1, list(/mob/living/simple_mob/animal/sif/sakimm = 10, /mob/living/simple_mob/animal/sif/sakimm/intelligent = 1)),
			loot_sub(5, list(/mob/living/simple_mob/animal/sif/savik)),
			loot_sub(1, list(/mob/living/simple_mob/animal/sif/shantak = 10, /mob/living/simple_mob/animal/sif/shantak/leader = 1)),
			loot_sub(1, list(/mob/living/simple_mob/animal/sif/siffet)),
			loot_sub(1, list(/mob/living/simple_mob/animal/sif/tymisian)),
			loot_sub(1, list(/mob/living/simple_mob/animal/giant_spider/electric = 5, /mob/living/simple_mob/animal/giant_spider/frost = 5, /mob/living/simple_mob/animal/giant_spider/hunter = 10, /mob/living/simple_mob/animal/giant_spider/ion = 5, /mob/living/simple_mob/animal/giant_spider/lurker = 10, /mob/living/simple_mob/animal/giant_spider/pepper = 10, /mob/living/simple_mob/animal/giant_spider/phorogenic = 10, /mob/living/simple_mob/animal/giant_spider/thermic = 5, /mob/living/simple_mob/animal/giant_spider/tunneler = 10, /mob/living/simple_mob/animal/giant_spider/webslinger = 5, /mob/living/simple_mob/animal/giant_spider/broodmother = 1)),
			loot_sub(1, list(/mob/living/simple_mob/creature/strong)),
			loot_sub(1, list(/mob/living/simple_mob/faithless/strong)),
			loot_sub(1, list(/mob/living/simple_mob/animal/goat)),
			loot_sub(1, list(/mob/living/simple_mob/animal/sif/shantak/leader = 1, /mob/living/simple_mob/animal/sif/shantak = 10)),
			loot_sub(1, list(/mob/living/simple_mob/animal/sif/savik)),
			loot_sub(1, list(/mob/living/simple_mob/animal/sif/hooligan_crab)),
			loot_sub(1, list(/mob/living/simple_mob/animal/space/alien = 50, /mob/living/simple_mob/animal/space/alien/drone = 40, /mob/living/simple_mob/animal/space/alien/sentinel = 25, /mob/living/simple_mob/animal/space/alien/sentinel/praetorian = 15, /mob/living/simple_mob/animal/space/alien/queen = 10, /mob/living/simple_mob/animal/space/alien/queen/empress = 5, /mob/living/simple_mob/animal/space/alien/queen/empress/mother = 1)),
			loot_sub(1, list(/mob/living/simple_mob/animal/space/bats/cult/strong)),
			loot_sub(1, list(/mob/living/simple_mob/animal/space/bear, /mob/living/simple_mob/animal/space/bear/brown)),
			loot_sub(1, list(/mob/living/simple_mob/animal/space/carp = 50, /mob/living/simple_mob/animal/space/carp/large = 10, /mob/living/simple_mob/animal/space/carp/large/huge = 5)),
			loot_sub(1, list(/mob/living/simple_mob/animal/space/goose)),
			loot_sub(1, list(/mob/living/simple_mob/vore/jelly)),
			loot_sub(1, list(/mob/living/simple_mob/animal/space/tree)),
			loot_sub(1, list(/mob/living/simple_mob/vore/aggressive/corrupthound = 10, /mob/living/simple_mob/vore/aggressive/corrupthound/prettyboi = 1)),
			loot_sub(1, list(/mob/living/simple_mob/vore/aggressive/deathclaw)),
			loot_sub(1, list(/mob/living/simple_mob/vore/aggressive/dino)),
			loot_sub(1, list(/mob/living/simple_mob/vore/aggressive/dragon)),
			loot_sub(1, list(/mob/living/simple_mob/vore/aggressive/dragon/virgo3b)),
			loot_sub(1, list(/mob/living/simple_mob/vore/aggressive/frog)),
			loot_sub(1, list(/mob/living/simple_mob/vore/aggressive/giant_snake)),
			loot_sub(1, list(/mob/living/simple_mob/vore/aggressive/mimic)),
			loot_sub(1, list(/mob/living/simple_mob/vore/aggressive/panther)),
			loot_sub(1, list(/mob/living/simple_mob/vore/aggressive/rat)),
			loot_sub(1, list(/mob/living/simple_mob/vore/bee)),
			loot_sub(1, list(/mob/living/simple_mob/vore/sect_drone = 10, /mob/living/simple_mob/vore/sect_queen = 1)),
			loot_sub(1, list(/mob/living/simple_mob/vore/solargrub)),
			loot_sub(1, list(/mob/living/simple_mob/vore/oregrub = 5, /mob/living/simple_mob/vore/oregrub/lava = 1)),
			loot_sub(1, list(/mob/living/simple_mob/vore/catgirl)),
			loot_sub(1, list(/mob/living/simple_mob/vore/wolfgirl)),
			loot_sub(1, list(/mob/living/simple_mob/vore/lamia, /mob/living/simple_mob/vore/lamia/albino, /mob/living/simple_mob/vore/lamia/albino/bra, /mob/living/simple_mob/vore/lamia/albino/shirt, /mob/living/simple_mob/vore/lamia/bra, /mob/living/simple_mob/vore/lamia/cobra, /mob/living/simple_mob/vore/lamia/cobra/bra, /mob/living/simple_mob/vore/lamia/cobra/shirt, /mob/living/simple_mob/vore/lamia/copper, /mob/living/simple_mob/vore/lamia/copper/bra, /mob/living/simple_mob/vore/lamia/copper/shirt, /mob/living/simple_mob/vore/lamia/green, /mob/living/simple_mob/vore/lamia/green/bra, /mob/living/simple_mob/vore/lamia/green/shirt, /mob/living/simple_mob/vore/lamia/zebra, /mob/living/simple_mob/vore/lamia/zebra/bra, /mob/living/simple_mob/vore/lamia/zebra/shirt)),
			loot_sub(1, list(/mob/living/simple_mob/humanoid/merc = 100, /mob/living/simple_mob/humanoid/merc/melee/sword = 50, /mob/living/simple_mob/humanoid/merc/ranged = 25, /mob/living/simple_mob/humanoid/merc/ranged/grenadier = 1, /mob/living/simple_mob/humanoid/merc/ranged/ionrifle = 10, /mob/living/simple_mob/humanoid/merc/ranged/laser = 5, /mob/living/simple_mob/humanoid/merc/ranged/rifle = 5, /mob/living/simple_mob/humanoid/merc/ranged/smg = 5, /mob/living/simple_mob/humanoid/merc/ranged/sniper = 1, /mob/living/simple_mob/humanoid/merc/ranged/space = 10, /mob/living/simple_mob/humanoid/merc/ranged/technician = 5)),
			loot_sub(1, list(/mob/living/simple_mob/humanoid/pirate = 3, /mob/living/simple_mob/humanoid/pirate/ranged = 1)),
			loot_sub(1, list(/mob/living/simple_mob/mechanical/combat_drone)),
			loot_sub(1, list(/mob/living/simple_mob/mechanical/corrupt_maint_drone)),
			loot_sub(1, list(/mob/living/simple_mob/mechanical/hivebot = 100, /mob/living/simple_mob/mechanical/hivebot/ranged_damage = 20, /mob/living/simple_mob/mechanical/hivebot/ranged_damage/backline = 10, /mob/living/simple_mob/mechanical/hivebot/ranged_damage/basic = 20, /mob/living/simple_mob/mechanical/hivebot/ranged_damage/dot = 5, /mob/living/simple_mob/mechanical/hivebot/ranged_damage/ion = 20, /mob/living/simple_mob/mechanical/hivebot/ranged_damage/laser = 10, /mob/living/simple_mob/mechanical/hivebot/ranged_damage/rapid = 2, /mob/living/simple_mob/mechanical/hivebot/ranged_damage/siege = 1, /mob/living/simple_mob/mechanical/hivebot/ranged_damage/siege/emp = 5, /mob/living/simple_mob/mechanical/hivebot/ranged_damage/siege/fragmentation = 1, /mob/living/simple_mob/mechanical/hivebot/ranged_damage/siege/radiation = 1, /mob/living/simple_mob/mechanical/hivebot/ranged_damage/strong = 3, /mob/living/simple_mob/mechanical/hivebot/ranged_damage/strong/guard = 3, /mob/living/simple_mob/mechanical/hivebot/support = 8, /mob/living/simple_mob/mechanical/hivebot/support/commander = 5, /mob/living/simple_mob/mechanical/hivebot/support/commander/autofollow = 10, /mob/living/simple_mob/mechanical/hivebot/swarm = 20, /mob/living/simple_mob/mechanical/hivebot/tank = 20, /mob/living/simple_mob/mechanical/hivebot/tank/armored = 20, /mob/living/simple_mob/mechanical/hivebot/tank/armored/anti_bullet = 20, /mob/living/simple_mob/mechanical/hivebot/tank/armored/anti_laser = 20, /mob/living/simple_mob/mechanical/hivebot/tank/armored/anti_melee = 20, /mob/living/simple_mob/mechanical/hivebot/tank/meatshield = 20)),
			loot_sub(1, list(/mob/living/simple_mob/mechanical/infectionbot)),
			loot_sub(1, list(/mob/living/simple_mob/mechanical/mining_drone)),
			loot_sub(1, list(/mob/living/simple_mob/mechanical/technomancer_golem)),
			loot_sub(1, list(/mob/living/simple_mob/mechanical/viscerator, /mob/living/simple_mob/mechanical/viscerator/piercing)),
			loot_sub(1, list(/mob/living/simple_mob/mechanical/wahlem)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/fox/syndicate)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/fox)),
			loot_sub(1, list(/mob/living/simple_mob/vore/jelly)),
			loot_sub(1, list(/mob/living/simple_mob/vore/otie/feral, /mob/living/simple_mob/vore/otie/feral/chubby, /mob/living/simple_mob/vore/otie/red, /mob/living/simple_mob/vore/otie/red/chubby)),
			loot_sub(1, list(/mob/living/simple_mob/shadekin/blue = 100, /mob/living/simple_mob/shadekin/green = 50, /mob/living/simple_mob/shadekin/orange = 20, /mob/living/simple_mob/shadekin/purple = 60, /mob/living/simple_mob/shadekin/red = 40, /mob/living/simple_mob/shadekin/yellow = 1)),
			loot_sub(1, list(/mob/living/simple_mob/vore/aggressive/corrupthound, /mob/living/simple_mob/vore/aggressive/corrupthound/prettyboi)),
			loot_sub(1, list(/mob/living/simple_mob/vore/aggressive/deathclaw)),
			loot_sub(1, list(/mob/living/simple_mob/vore/aggressive/dino)),
			loot_sub(1, list(/mob/living/simple_mob/vore/aggressive/dragon)),
			loot_sub(1, list(/mob/living/simple_mob/vore/aggressive/dragon/virgo3b)),
			loot_sub(1, list(/mob/living/simple_mob/vore/aggressive/frog)),
			loot_sub(1, list(/mob/living/simple_mob/vore/aggressive/giant_snake)),
			loot_sub(1, list(/mob/living/simple_mob/vore/aggressive/mimic)),
			loot_sub(1, list(/mob/living/simple_mob/vore/aggressive/panther)),
			loot_sub(1, list(/mob/living/simple_mob/vore/aggressive/rat)),
			loot_sub(1, list(/mob/living/simple_mob/vore/bee)),
			loot_sub(1, list(/mob/living/simple_mob/vore/catgirl)),
			loot_sub(1, list(/mob/living/simple_mob/vore/cookiegirl)),
			loot_sub(1, list(/mob/living/simple_mob/vore/fennec)),
			loot_sub(1, list(/mob/living/simple_mob/vore/fennix)),
			loot_sub(1, list(/mob/living/simple_mob/vore/hippo)),
			loot_sub(1, list(/mob/living/simple_mob/vore/horse)),
			loot_sub(1, list(/mob/living/simple_mob/vore/oregrub)),
			loot_sub(1, list(/mob/living/simple_mob/vore/rabbit)),
			loot_sub(1, list(/mob/living/simple_mob/vore/redpanda = 50, /mob/living/simple_mob/vore/redpanda/fae = 1)),
			loot_sub(1, list(/mob/living/simple_mob/vore/sect_drone = 10, /mob/living/simple_mob/vore/sect_queen = 1)),
			loot_sub(1, list(/mob/living/simple_mob/vore/solargrub)),
			loot_sub(1, list(/mob/living/simple_mob/vore/woof)),
			loot_sub(1, list(/mob/living/simple_mob/vore/alienanimals/space_ghost)),
			loot_sub(1, list(/mob/living/simple_mob/vore/alienanimals/catslug)),
			loot_sub(1, list(/mob/living/simple_mob/vore/alienanimals/space_jellyfish)),
			loot_sub(1, list(/mob/living/simple_mob/vore/alienanimals/startreader)),
			loot_sub(1, list(/mob/living/simple_mob/vore/bigdragon, /mob/living/simple_mob/vore/bigdragon/friendly)),
			loot_sub(1, list(/mob/living/simple_mob/vore/leopardmander = 50, /mob/living/simple_mob/vore/leopardmander/blue = 10, /mob/living/simple_mob/vore/leopardmander/exotic = 1)),
			loot_sub(1, list(/mob/living/simple_mob/vore/sheep)),
			loot_sub(1, list(/mob/living/simple_mob/vore/weretiger)))))

/obj/random/mob/semirandom_mob_spawner/animal
	name = "Semi-Random Animal"
	desc = "Spawns groups of non-hostile mobs that are all of the same theme type/theme."
	icon_state = "animal"
	mob_faction = "animal"
	overwrite_hostility = 1
	mob_hostile = 0

CAPABILITIES(/obj/random/mob/semirandom_mob_spawner/animal)
	configure(loot(
		per_round = TRUE,
		table = list(
			loot_sub(25, list(/mob/living/simple_mob/animal/goat)),
			loot_sub(25, list(/mob/living/simple_mob/animal/passive/bird, /mob/living/simple_mob/animal/passive/bird/azure_tit, /mob/living/simple_mob/animal/passive/bird/black_bird, /mob/living/simple_mob/animal/passive/bird/european_robin, /mob/living/simple_mob/animal/passive/bird/goldcrest, /mob/living/simple_mob/animal/passive/bird/ringneck_dove, /mob/living/simple_mob/animal/passive/bird/parrot, /mob/living/simple_mob/animal/passive/bird/parrot/black_headed_caique, /mob/living/simple_mob/animal/passive/bird/parrot/budgerigar, /mob/living/simple_mob/animal/passive/bird/parrot/budgerigar/blue, /mob/living/simple_mob/animal/passive/bird/parrot/budgerigar/bluegreen, /mob/living/simple_mob/animal/passive/bird/parrot/cockatiel, /mob/living/simple_mob/animal/passive/bird/parrot/cockatiel/grey, /mob/living/simple_mob/animal/passive/bird/parrot/cockatiel/white, /mob/living/simple_mob/animal/passive/bird/parrot/cockatiel/yellowish, /mob/living/simple_mob/animal/passive/bird/parrot/eclectus, /mob/living/simple_mob/animal/passive/bird/parrot/grey_parrot, /mob/living/simple_mob/animal/passive/bird/parrot/kea, /mob/living/simple_mob/animal/passive/bird/parrot/pink_cockatoo, /mob/living/simple_mob/animal/passive/bird/parrot/sulphur_cockatoo, /mob/living/simple_mob/animal/passive/bird/parrot/white_caique, /mob/living/simple_mob/animal/passive/bird/parrot/white_cockatoo, /mob/living/simple_mob/animal/space/goose)),
			loot_sub(25, list(/mob/living/simple_mob/animal/passive/cat, /mob/living/simple_mob/animal/passive/cat/black)),
			loot_sub(25, list(/mob/living/simple_mob/animal/passive/chick, /mob/living/simple_mob/animal/passive/chicken)),
			loot_sub(25, list(/mob/living/simple_mob/animal/passive/cow)),
			loot_sub(10, list(/mob/living/simple_mob/animal/passive/dog/brittany)),
			loot_sub(10, list(/mob/living/simple_mob/animal/passive/dog/corgi)),
			loot_sub(10, list(/mob/living/simple_mob/animal/passive/dog/tamaskan)),
			loot_sub(25, list(/mob/living/simple_mob/animal/passive/fox)),
			loot_sub(25, list(/mob/living/simple_mob/animal/passive/hare)),
			loot_sub(10, list(/mob/living/simple_mob/animal/passive/lizard)),
			loot_sub(15, list(/mob/living/simple_mob/animal/passive/mouse)),
			loot_sub(5, list(/mob/living/simple_mob/animal/passive/mouse/jerboa)),
			loot_sub(10, list(/mob/living/simple_mob/animal/passive/opossum)),
			loot_sub(10, list(/mob/living/simple_mob/animal/passive/pillbug)),
			loot_sub(10, list(/mob/living/simple_mob/animal/passive/snake)),
			loot_sub(10, list(/mob/living/simple_mob/animal/passive/snake/red)),
			loot_sub(10, list(/mob/living/simple_mob/animal/passive/snake/python)),
			loot_sub(10, list(/mob/living/simple_mob/animal/passive/tindalos)),
			loot_sub(10, list(/mob/living/simple_mob/animal/passive/yithian)),
			loot_sub(10, list(/mob/living/simple_mob/vore/wolf = 10, /mob/living/simple_mob/vore/wolf/direwolf = 5, /mob/living/simple_mob/vore/greatwolf = 1, /mob/living/simple_mob/vore/greatwolf/black = 1, /mob/living/simple_mob/vore/greatwolf/grey = 1)),
			loot_sub(10, list(/mob/living/simple_mob/vore/rabbit)),
			loot_sub(10, list(/mob/living/simple_mob/vore/redpanda)),
			loot_sub(1, list(/mob/living/simple_mob/vore/woof)),
			loot_sub(10, list(/mob/living/simple_mob/vore/fennec)),
			loot_sub(1, list(/mob/living/simple_mob/vore/fennix)),
			loot_sub(5, list(/mob/living/simple_mob/vore/hippo)),
			loot_sub(25, list(/mob/living/simple_mob/vore/horse)),
			loot_sub(10, list(/mob/living/simple_mob/vore/bee)),
			loot_sub(1, list(/mob/living/simple_mob/animal/space/bear, /mob/living/simple_mob/animal/space/bear/brown)),
			loot_sub(5, list(/mob/living/simple_mob/vore/otie/feral = 50, /mob/living/simple_mob/vore/otie/feral/chubby = 10, /mob/living/simple_mob/vore/otie/red = 5, /mob/living/simple_mob/vore/otie/red/chubby = 1)),
			loot_sub(15, list(/mob/living/simple_mob/vore/aggressive/rat)),
			loot_sub(5, list(/mob/living/simple_mob/animal/sif/diyaab)),
			loot_sub(5, list(/mob/living/simple_mob/animal/sif/duck)),
			loot_sub(5, list(/mob/living/simple_mob/animal/sif/frostfly)),
			loot_sub(5, list(/mob/living/simple_mob/animal/sif/glitterfly = 50, /mob/living/simple_mob/animal/sif/glitterfly/rare = 1)),
			loot_sub(5, list(/mob/living/simple_mob/animal/sif/kururak = 10, /mob/living/simple_mob/animal/sif/kururak/leader = 1, /mob/living/simple_mob/animal/sif/kururak/hibernate = 2)),
			loot_sub(5, list(/mob/living/simple_mob/animal/sif/sakimm = 10, /mob/living/simple_mob/animal/sif/sakimm/intelligent = 1)),
			loot_sub(5, list(/mob/living/simple_mob/animal/sif/savik)),
			loot_sub(5, list(/mob/living/simple_mob/animal/sif/shantak = 10, /mob/living/simple_mob/animal/sif/shantak/leader = 1)),
			loot_sub(5, list(/mob/living/simple_mob/animal/sif/siffet)),
			loot_sub(5, list(/mob/living/simple_mob/animal/sif/tymisian)),
			loot_sub(10, list(/mob/living/simple_mob/vore/alienanimals/teppi)),
			loot_sub(5, list(/mob/living/simple_mob/vore/alienanimals/dustjumper)),
			loot_sub(5, list(/mob/living/simple_mob/vore/alienanimals/space_jellyfish)),
			loot_sub(5, list(/mob/living/simple_mob/vore/alienanimals/space_ghost)),
			loot_sub(5, list(/mob/living/simple_mob/vore/leopardmander = 50, /mob/living/simple_mob/vore/leopardmander/blue = 10, /mob/living/simple_mob/vore/leopardmander/exotic = 1)),
			loot_sub(5, list(/mob/living/simple_mob/vore/sheep)),
			loot_sub(5, list(/mob/living/simple_mob/vore/weretiger)),
			loot_sub(5, list(/mob/living/simple_mob/vore/alienanimals/skeleton)))))

/obj/random/mob/semirandom_mob_spawner/monster
	name = "Semi-Random Monster"
	desc = "Spawns groups of hostile mobs that are all of the same theme type/theme."
	overwrite_hostility = 1
	mob_faction = "monster"
	mob_hostile = 1
	mob_retaliate = 1

CAPABILITIES(/obj/random/mob/semirandom_mob_spawner/monster)
	configure(loot(
		per_round = TRUE,
		table = list(
			loot_sub(100, list(/mob/living/simple_mob/animal/giant_spider/electric = 5, /mob/living/simple_mob/animal/giant_spider/frost = 5, /mob/living/simple_mob/animal/giant_spider/hunter = 10, /mob/living/simple_mob/animal/giant_spider/ion = 5, /mob/living/simple_mob/animal/giant_spider/lurker = 10, /mob/living/simple_mob/animal/giant_spider/pepper = 10, /mob/living/simple_mob/animal/giant_spider/phorogenic = 10, /mob/living/simple_mob/animal/giant_spider/thermic = 5, /mob/living/simple_mob/animal/giant_spider/tunneler = 10, /mob/living/simple_mob/animal/giant_spider/webslinger = 5)),
			loot_sub(1, list(/mob/living/simple_mob/shadekin/red = 5, /mob/living/simple_mob/shadekin/orange = 1, /mob/living/simple_mob/shadekin/purple = 10)),
			loot_sub(40, list(/mob/living/simple_mob/vore/wolf = 10, /mob/living/simple_mob/vore/wolf/direwolf = 5, /mob/living/simple_mob/vore/greatwolf = 1, /mob/living/simple_mob/vore/greatwolf/black = 1, /mob/living/simple_mob/vore/greatwolf/grey = 1)),
			loot_sub(40, list(/mob/living/simple_mob/creature/strong)),
			loot_sub(20, list(/mob/living/simple_mob/faithless/strong)),
			loot_sub(1, list(/mob/living/simple_mob/animal/goat)),
			loot_sub(50, list(/mob/living/simple_mob/animal/sif/shantak/leader = 1, /mob/living/simple_mob/animal/sif/shantak = 10)),
			loot_sub(20, list(/mob/living/simple_mob/animal/sif/savik)),
			loot_sub(10, list(/mob/living/simple_mob/animal/sif/hooligan_crab)),
			loot_sub(40, list(/mob/living/simple_mob/animal/space/alien = 50, /mob/living/simple_mob/animal/space/alien/drone = 40, /mob/living/simple_mob/animal/space/alien/sentinel = 25, /mob/living/simple_mob/animal/space/alien/sentinel/praetorian = 15, /mob/living/simple_mob/animal/space/alien/queen = 10, /mob/living/simple_mob/animal/space/alien/queen/empress = 5, /mob/living/simple_mob/animal/space/alien/queen/empress/mother = 1)),
			loot_sub(40, list(/mob/living/simple_mob/animal/space/bats/cult/strong)),
			loot_sub(40, list(/mob/living/simple_mob/animal/space/bear, /mob/living/simple_mob/animal/space/bear/brown)),
			loot_sub(50, list(/mob/living/simple_mob/animal/space/carp = 50, /mob/living/simple_mob/animal/space/carp/large = 10, /mob/living/simple_mob/animal/space/carp/large/huge = 5)),
			loot_sub(50, list(/mob/living/simple_mob/animal/space/goose)),
			loot_sub(40, list(/mob/living/simple_mob/vore/jelly)),
			loot_sub(15, list(/mob/living/simple_mob/animal/space/tree)),
			loot_sub(40, list(/mob/living/simple_mob/vore/otie/feral = 50, /mob/living/simple_mob/vore/otie/feral/chubby = 10, /mob/living/simple_mob/vore/otie/red = 5, /mob/living/simple_mob/vore/otie/red/chubby = 1)),
			loot_sub(50, list(/mob/living/simple_mob/vore/aggressive/corrupthound = 10, /mob/living/simple_mob/vore/aggressive/corrupthound/prettyboi = 1)),
			loot_sub(40, list(/mob/living/simple_mob/vore/aggressive/deathclaw)),
			loot_sub(40, list(/mob/living/simple_mob/vore/aggressive/dino)),
			loot_sub(40, list(/mob/living/simple_mob/vore/aggressive/dragon)),
			loot_sub(40, list(/mob/living/simple_mob/vore/aggressive/dragon/virgo3b)),
			loot_sub(40, list(/mob/living/simple_mob/vore/aggressive/frog)),
			loot_sub(40, list(/mob/living/simple_mob/vore/aggressive/giant_snake)),
			loot_sub(40, list(/mob/living/simple_mob/vore/aggressive/mimic)),
			loot_sub(25, list(/mob/living/simple_mob/vore/aggressive/panther)),
			loot_sub(50, list(/mob/living/simple_mob/vore/aggressive/rat)),
			loot_sub(40, list(/mob/living/simple_mob/vore/bee)),
			loot_sub(20, list(/mob/living/simple_mob/vore/sect_drone = 10, /mob/living/simple_mob/vore/sect_queen = 1)),
			loot_sub(15, list(/mob/living/simple_mob/vore/solargrub)),
			loot_sub(15, list(/mob/living/simple_mob/vore/oregrub = 5, /mob/living/simple_mob/vore/oregrub/lava = 1)),
			loot_sub(15, list(/mob/living/simple_mob/vore/alienanimals/teppi)),
			loot_sub(5, list(/mob/living/simple_mob/vore/alienanimals/space_jellyfish)),
			loot_sub(5, list(/mob/living/simple_mob/vore/alienanimals/space_ghost)),
			loot_sub(5, list(/mob/living/simple_mob/vore/leopardmander = 50, /mob/living/simple_mob/vore/leopardmander/blue = 10, /mob/living/simple_mob/vore/leopardmander/exotic = 1)),
			loot_sub(5, list(/mob/living/simple_mob/vore/sheep)),
			loot_sub(5, list(/mob/living/simple_mob/vore/weretiger)),
			loot_sub(5, list(/mob/living/simple_mob/vore/alienanimals/skeleton)),
			loot_sub(5, list(/mob/living/simple_mob/vore/alienanimals/catslug)))))

/obj/random/mob/semirandom_mob_spawner/humanoid
	name = "Semi-Random Humanoid"
	desc = "Spawns groups of humanoid mobs that may or may not be hostile, all of the same theme type/theme."
	icon_state = "humanoid"
	mob_faction = "humanoid"

CAPABILITIES(/obj/random/mob/semirandom_mob_spawner/humanoid)
	configure(loot(
		per_round = TRUE,
		table = list(
			loot_sub(1, list(/mob/living/simple_mob/shadekin/blue = 25, /mob/living/simple_mob/shadekin/green = 10, /mob/living/simple_mob/shadekin/purple = 1)),
			loot_sub(100, list(/mob/living/simple_mob/vore/catgirl)),
			loot_sub(100, list(/mob/living/simple_mob/vore/wolfgirl)),
			loot_sub(100, list(/mob/living/simple_mob/vore/lamia, /mob/living/simple_mob/vore/lamia/albino, /mob/living/simple_mob/vore/lamia/albino/bra, /mob/living/simple_mob/vore/lamia/albino/shirt, /mob/living/simple_mob/vore/lamia/bra, /mob/living/simple_mob/vore/lamia/cobra, /mob/living/simple_mob/vore/lamia/cobra/bra, /mob/living/simple_mob/vore/lamia/cobra/shirt, /mob/living/simple_mob/vore/lamia/copper, /mob/living/simple_mob/vore/lamia/copper/bra, /mob/living/simple_mob/vore/lamia/copper/shirt, /mob/living/simple_mob/vore/lamia/green, /mob/living/simple_mob/vore/lamia/green/bra, /mob/living/simple_mob/vore/lamia/green/shirt, /mob/living/simple_mob/vore/lamia/zebra, /mob/living/simple_mob/vore/lamia/zebra/bra, /mob/living/simple_mob/vore/lamia/zebra/shirt)),
			loot_sub(5, list(/mob/living/simple_mob/humanoid/merc = 100, /mob/living/simple_mob/humanoid/merc/melee/sword = 50, /mob/living/simple_mob/humanoid/merc/ranged = 25, /mob/living/simple_mob/humanoid/merc/ranged/grenadier = 1, /mob/living/simple_mob/humanoid/merc/ranged/ionrifle = 10, /mob/living/simple_mob/humanoid/merc/ranged/laser = 5, /mob/living/simple_mob/humanoid/merc/ranged/rifle = 5, /mob/living/simple_mob/humanoid/merc/ranged/smg = 5, /mob/living/simple_mob/humanoid/merc/ranged/sniper = 1, /mob/living/simple_mob/humanoid/merc/ranged/space = 10, /mob/living/simple_mob/humanoid/merc/ranged/technician = 5)),
			loot_sub(50, list(/mob/living/simple_mob/humanoid/pirate = 3, /mob/living/simple_mob/humanoid/pirate/ranged = 1)))))

// I am not familiar enough with robots to know which ones are fun to fight so this list isn't weighted at all SO YOU KNOW. Be careful.
/obj/random/mob/semirandom_mob_spawner/robot
	name = "Semi-Random Robot"
	desc = "Spawns groups of robotic mobs that are probably hostile, all of the same theme type/theme."
	icon_state = "robot"
	mob_faction = "robot"

CAPABILITIES(/obj/random/mob/semirandom_mob_spawner/robot)
	configure(loot(
		per_round = TRUE,
		table = list(
			loot_sub(1, list(/mob/living/simple_mob/mechanical/combat_drone)),
			loot_sub(1, list(/mob/living/simple_mob/mechanical/corrupt_maint_drone)),
			loot_sub(1, list(/mob/living/simple_mob/mechanical/hivebot = 100, /mob/living/simple_mob/mechanical/hivebot/ranged_damage = 20, /mob/living/simple_mob/mechanical/hivebot/ranged_damage/backline = 10, /mob/living/simple_mob/mechanical/hivebot/ranged_damage/basic = 20, /mob/living/simple_mob/mechanical/hivebot/ranged_damage/dot = 5, /mob/living/simple_mob/mechanical/hivebot/ranged_damage/ion = 20, /mob/living/simple_mob/mechanical/hivebot/ranged_damage/laser = 10, /mob/living/simple_mob/mechanical/hivebot/ranged_damage/rapid = 2, /mob/living/simple_mob/mechanical/hivebot/ranged_damage/siege = 1, /mob/living/simple_mob/mechanical/hivebot/ranged_damage/siege/emp = 5, /mob/living/simple_mob/mechanical/hivebot/ranged_damage/siege/fragmentation = 1, /mob/living/simple_mob/mechanical/hivebot/ranged_damage/siege/radiation = 1, /mob/living/simple_mob/mechanical/hivebot/ranged_damage/strong = 3, /mob/living/simple_mob/mechanical/hivebot/ranged_damage/strong/guard = 3, /mob/living/simple_mob/mechanical/hivebot/support = 8, /mob/living/simple_mob/mechanical/hivebot/support/commander = 5, /mob/living/simple_mob/mechanical/hivebot/support/commander/autofollow = 10, /mob/living/simple_mob/mechanical/hivebot/swarm = 20, /mob/living/simple_mob/mechanical/hivebot/tank = 20, /mob/living/simple_mob/mechanical/hivebot/tank/armored = 20, /mob/living/simple_mob/mechanical/hivebot/tank/armored/anti_bullet = 20, /mob/living/simple_mob/mechanical/hivebot/tank/armored/anti_laser = 20, /mob/living/simple_mob/mechanical/hivebot/tank/armored/anti_melee = 20, /mob/living/simple_mob/mechanical/hivebot/tank/meatshield = 20)),
			loot_sub(1, list(/mob/living/simple_mob/mechanical/infectionbot)),
			loot_sub(1, list(/mob/living/simple_mob/mechanical/mining_drone)),
			loot_sub(1, list(/mob/living/simple_mob/mechanical/technomancer_golem)),
			loot_sub(1, list(/mob/living/simple_mob/mechanical/viscerator, /mob/living/simple_mob/mechanical/viscerator/piercing)),
			loot_sub(1, list(/mob/living/simple_mob/mechanical/wahlem)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/fox/syndicate)))))

/obj/random/mob/semirandom_mob_spawner/fish
	name = "Semi-Random Fish"
	desc = "Spawns groups of fish, all of the same theme type/theme."
	icon_state = "fish"
	mob_faction = "fish"
	overwrite_hostility = 1
	mob_hostile = 0
	mob_retaliate = 0

CAPABILITIES(/obj/random/mob/semirandom_mob_spawner/fish)
	configure(loot(
		per_round = TRUE,
		table = list(
			loot_sub(20, list(/mob/living/simple_mob/animal/passive/fish/bass)),
			loot_sub(20, list(/mob/living/simple_mob/animal/passive/fish/icebass)),
			loot_sub(20, list(/mob/living/simple_mob/animal/passive/fish/javelin)),
			loot_sub(10, list(/mob/living/simple_mob/animal/passive/fish/koi)),
			loot_sub(5, list(/mob/living/simple_mob/animal/passive/fish/measelshark)),
			loot_sub(20, list(/mob/living/simple_mob/animal/passive/fish/murkin)),
			loot_sub(20, list(/mob/living/simple_mob/animal/passive/fish/perch)),
			loot_sub(20, list(/mob/living/simple_mob/animal/passive/fish/pike)),
			loot_sub(10, list(/mob/living/simple_mob/animal/passive/fish/rockfish)),
			loot_sub(20, list(/mob/living/simple_mob/animal/passive/fish/salmon)),
			loot_sub(5, list(/mob/living/simple_mob/animal/passive/fish/solarfish)),
			loot_sub(20, list(/mob/living/simple_mob/animal/passive/fish/trout)),
			loot_sub(10, list(/mob/living/simple_mob/animal/passive/crab)),
			loot_sub(1, list(/mob/living/simple_mob/animal/sif/hooligan_crab)))))

/obj/random/mob/semirandom_mob_spawner/bird
	name = "Semi-Random Bird"
	desc = "Spawns groups of bird, all of the same theme type/theme."
	icon_state = "bird"
	mob_faction = "bird"

CAPABILITIES(/obj/random/mob/semirandom_mob_spawner/bird)
	configure(loot(
		per_round = TRUE,
		table = list(
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/bird)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/bird/azure_tit)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/bird/black_bird)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/bird/european_robin)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/bird/goldcrest)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/bird/ringneck_dove)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/bird/parrot)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/bird/parrot/black_headed_caique)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/bird/parrot/budgerigar)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/bird/parrot/budgerigar/blue)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/bird/parrot/budgerigar/bluegreen)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/bird/parrot/cockatiel)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/bird/parrot/cockatiel/grey)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/bird/parrot/cockatiel/white)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/bird/parrot/cockatiel/yellowish)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/bird/parrot/eclectus)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/bird/parrot/grey_parrot)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/bird/parrot/kea)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/bird/parrot/pink_cockatoo)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/bird/parrot/sulphur_cockatoo)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/bird/parrot/white_caique)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/bird/parrot/white_cockatoo)),
			loot_sub(1, list(/mob/living/simple_mob/animal/space/goose)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/chicken)),
			loot_sub(1, list(/mob/living/simple_mob/animal/passive/penguin)))))

/obj/random/mob/semirandom_mob_spawner/vore
	name = "Semi-Random Voremob"
	desc = "Spawns groups of voremobs, all of the same theme type/theme."
	icon_state = "vore"
	mob_faction = "vore"

CAPABILITIES(/obj/random/mob/semirandom_mob_spawner/vore)
	configure(loot(
		per_round = TRUE,
		table = list(
			loot_sub(100, list(/mob/living/simple_mob/vore/wolf/direwolf = 5, /mob/living/simple_mob/vore/greatwolf = 1, /mob/living/simple_mob/vore/greatwolf/black = 1, /mob/living/simple_mob/vore/greatwolf/grey = 1)),
			loot_sub(70, list(/mob/living/simple_mob/vore/jelly)),
			loot_sub(50, list(/mob/living/simple_mob/vore/otie/feral, /mob/living/simple_mob/vore/otie/feral/chubby, /mob/living/simple_mob/vore/otie/red, /mob/living/simple_mob/vore/otie/red/chubby)),
			loot_sub(1, list(/mob/living/simple_mob/shadekin/blue = 100, /mob/living/simple_mob/shadekin/green = 50, /mob/living/simple_mob/shadekin/orange = 20, /mob/living/simple_mob/shadekin/purple = 60, /mob/living/simple_mob/shadekin/red = 40, /mob/living/simple_mob/shadekin/yellow = 1)),
			loot_sub(70, list(/mob/living/simple_mob/vore/aggressive/corrupthound, /mob/living/simple_mob/vore/aggressive/corrupthound/prettyboi)),
			loot_sub(70, list(/mob/living/simple_mob/vore/aggressive/deathclaw)),
			loot_sub(100, list(/mob/living/simple_mob/vore/aggressive/dino)),
			loot_sub(100, list(/mob/living/simple_mob/vore/aggressive/dragon)),
			loot_sub(100, list(/mob/living/simple_mob/vore/aggressive/dragon/virgo3b)),
			loot_sub(100, list(/mob/living/simple_mob/vore/aggressive/frog)),
			loot_sub(100, list(/mob/living/simple_mob/vore/aggressive/giant_snake)),
			loot_sub(50, list(/mob/living/simple_mob/vore/aggressive/mimic)),
			loot_sub(70, list(/mob/living/simple_mob/vore/aggressive/panther)),
			loot_sub(100, list(/mob/living/simple_mob/vore/aggressive/rat)),
			loot_sub(100, list(/mob/living/simple_mob/vore/bee)),
			loot_sub(100, list(/mob/living/simple_mob/vore/catgirl)),
			loot_sub(100, list(/mob/living/simple_mob/vore/wolftaur)),
			loot_sub(100, list(/mob/living/simple_mob/vore/cookiegirl)),
			loot_sub(100, list(/mob/living/simple_mob/vore/fennec)),
			loot_sub(50, list(/mob/living/simple_mob/vore/fennix)),
			loot_sub(70, list(/mob/living/simple_mob/vore/hippo)),
			loot_sub(100, list(/mob/living/simple_mob/vore/horse)),
			loot_sub(100, list(/mob/living/simple_mob/vore/raptor)),
			loot_sub(100, list(/mob/living/simple_mob/vore/succubus)),
			loot_sub(50, list(/mob/living/simple_mob/vore/vampire)),
			loot_sub(1, list(/mob/living/simple_mob/vore/vampire/queen)),
			loot_sub(50, list(/mob/living/simple_mob/vore/bat)),
			loot_sub(10, list(/mob/living/simple_mob/vore/scel)),
			loot_sub(100, list(/mob/living/simple_mob/vore/lamia, /mob/living/simple_mob/vore/lamia/albino, /mob/living/simple_mob/vore/lamia/albino/bra, /mob/living/simple_mob/vore/lamia/albino/shirt, /mob/living/simple_mob/vore/lamia/bra, /mob/living/simple_mob/vore/lamia/cobra, /mob/living/simple_mob/vore/lamia/cobra/bra, /mob/living/simple_mob/vore/lamia/cobra/shirt, /mob/living/simple_mob/vore/lamia/copper, /mob/living/simple_mob/vore/lamia/copper/bra, /mob/living/simple_mob/vore/lamia/copper/shirt, /mob/living/simple_mob/vore/lamia/green, /mob/living/simple_mob/vore/lamia/green/bra, /mob/living/simple_mob/vore/lamia/green/shirt, /mob/living/simple_mob/vore/lamia/zebra, /mob/living/simple_mob/vore/lamia/zebra/bra, /mob/living/simple_mob/vore/lamia/zebra/shirt)),
			loot_sub(100, list(/mob/living/simple_mob/vore/rabbit)),
			loot_sub(100, list(/mob/living/simple_mob/vore/redpanda = 50, /mob/living/simple_mob/vore/redpanda/fae = 1)),
			loot_sub(50, list(/mob/living/simple_mob/vore/sect_drone = 10, /mob/living/simple_mob/vore/sect_queen = 1)),
			loot_sub(100, list(/mob/living/simple_mob/vore/solargrub)),
			loot_sub(1, list(/mob/living/simple_mob/vore/woof)),
			loot_sub(25, list(/mob/living/simple_mob/vore/alienanimals/teppi)))))

/obj/random/mob/semirandom_mob_spawner/sus
	name = "Weird shit"
	desc = "Spawns groups of weird stuff, all of the same theme type/theme. Don't put this on normal maps."
	icon_state = "sus"
	mob_faction = "sus"

CAPABILITIES(/obj/random/mob/semirandom_mob_spawner/sus)
	configure(loot(
		per_round = TRUE,
		table = list(
			loot_sub(1, list(/mob/living/simple_mob/vore/woof/hostile/melee = 100, /mob/living/simple_mob/vore/woof/hostile/ranged = 20, /mob/living/simple_mob/vore/woof/hostile/horrible = 10, /mob/living/simple_mob/vore/woof/hostile/terrible = 5, /mob/living/simple_mob/vore/woof/cass = 1)),
			loot_sub(1, list(/mob/living/simple_mob/mechanical/mecha/combat/gygax/dark/advanced)))))

/obj/random/mob/semirandom_mob_spawner/mecha
	name = "Semi-Random Mecha"
	desc = "Spawns groups of mechs, all of the same theme type/theme. Don't put this on normal maps."
	icon_state = "mecha"
	mob_faction = "mecha"

CAPABILITIES(/obj/random/mob/semirandom_mob_spawner/mecha)
	configure(loot(
		per_round = TRUE,
		table = list(
			loot_sub(1, list(/mob/living/simple_mob/mechanical/mecha/combat/durand)),
			loot_sub(1, list(/mob/living/simple_mob/mechanical/mecha/combat/durand/defensive)),
			loot_sub(1, list(/mob/living/simple_mob/mechanical/mecha/combat/durand/defensive/mercenary)),
			loot_sub(1, list(/mob/living/simple_mob/mechanical/mecha/combat/gygax)),
			loot_sub(1, list(/mob/living/simple_mob/mechanical/mecha/combat/gygax/dark)),
			loot_sub(1, list(/mob/living/simple_mob/mechanical/mecha/combat/gygax/dark/advanced)),
			loot_sub(1, list(/mob/living/simple_mob/mechanical/mecha/combat/gygax/manned)),
			loot_sub(1, list(/mob/living/simple_mob/mechanical/mecha/combat/gygax/medgax)),
			loot_sub(1, list(/mob/living/simple_mob/mechanical/mecha/combat/marauder)),
			loot_sub(1, list(/mob/living/simple_mob/mechanical/mecha/combat/marauder/mauler)),
			loot_sub(1, list(/mob/living/simple_mob/mechanical/mecha/combat/marauder/seraph)),
			loot_sub(1, list(/mob/living/simple_mob/mechanical/mecha/combat/phazon)),
			loot_sub(1, list(/mob/living/simple_mob/mechanical/mecha/hoverpod)),
			loot_sub(1, list(/mob/living/simple_mob/mechanical/mecha/hoverpod/manned)),
			loot_sub(1, list(/mob/living/simple_mob/mechanical/mecha/odysseus)),
			loot_sub(1, list(/mob/living/simple_mob/mechanical/mecha/odysseus/manned)),
			loot_sub(1, list(/mob/living/simple_mob/mechanical/mecha/odysseus/murdysseus)),
			loot_sub(1, list(/mob/living/simple_mob/mechanical/mecha/odysseus/murdysseus/manned)),
			loot_sub(1, list(/mob/living/simple_mob/mechanical/mecha/ripley)),
			loot_sub(1, list(/mob/living/simple_mob/mechanical/mecha/ripley/blue_flames)),
			loot_sub(1, list(/mob/living/simple_mob/mechanical/mecha/ripley/deathripley)),
			loot_sub(1, list(/mob/living/simple_mob/mechanical/mecha/ripley/deathripley/manned)),
			loot_sub(1, list(/mob/living/simple_mob/mechanical/mecha/ripley/firefighter)),
			loot_sub(1, list(/mob/living/simple_mob/mechanical/mecha/ripley/firefighter/manned)),
			loot_sub(1, list(/mob/living/simple_mob/mechanical/mecha/ripley/manned)),
			loot_sub(1, list(/mob/living/simple_mob/mechanical/mecha/ripley/red_flames)))))

/obj/random/mob/semirandom_mob_spawner/monster/b
	mob_faction = "monsterb"

/obj/random/mob/semirandom_mob_spawner/monster/c
	mob_faction = "monsterc"

/obj/random/mob/semirandom_mob_spawner/monster/d
	mob_faction = "monsterd"

/obj/random/mob/semirandom_mob_spawner/monster/e
	mob_faction = "monstere"

/obj/random/mob/semirandom_mob_spawner/monster/f
	mob_faction = "monsterf"

/obj/random/mob/semirandom_mob_spawner/animal/b
	mob_faction = "animalb"

/obj/random/mob/semirandom_mob_spawner/animal/c
	mob_faction = "animalc"

/obj/random/mob/semirandom_mob_spawner/animal/d
	mob_faction = "animald"

/obj/random/mob/semirandom_mob_spawner/animal/e
	mob_faction = "animale"

/obj/random/mob/semirandom_mob_spawner/animal/f
	mob_faction = "animalf"

/obj/random/mob/semirandom_mob_spawner/animal/retaliate
	mob_faction = "retanimala"
	overwrite_hostility = 1
	mob_hostile = 0
	mob_retaliate = 1

/obj/random/mob/semirandom_mob_spawner/animal/retaliate/b
	mob_faction = "retanimalb"

/obj/random/mob/semirandom_mob_spawner/animal/retaliate/c
	mob_faction = "retanimalc"

/obj/random/mob/semirandom_mob_spawner/animal/hostile
	mob_faction = "hosanimala"
	overwrite_hostility = 1
	mob_hostile = 1
	mob_retaliate = 1

/obj/random/mob/semirandom_mob_spawner/animal/hostile/b
	mob_faction = "hosanimalb"

/obj/random/mob/semirandom_mob_spawner/animal/hostile/c
	mob_faction = "hosanimalc"


/obj/random/mob/semirandom_mob_spawner/humanoid/b
	mob_faction = "humanoidb"

/obj/random/mob/semirandom_mob_spawner/humanoid/c
	mob_faction = "humanoidc"

/obj/random/mob/semirandom_mob_spawner/humanoid/d
	mob_faction = "humanoidd"

/obj/random/mob/semirandom_mob_spawner/humanoid/e
	mob_faction = "humanoide"

/obj/random/mob/semirandom_mob_spawner/humanoid/f
	mob_faction = "humanoidf"

/obj/random/mob/semirandom_mob_spawner/humanoid/retaliate
	mob_faction = "rethumanoida"
	overwrite_hostility = 1
	mob_hostile = 0
	mob_retaliate = 1

/obj/random/mob/semirandom_mob_spawner/humanoid/retaliate/b
	mob_faction = "rethumanoidb"

/obj/random/mob/semirandom_mob_spawner/humanoid/retaliate/c
	mob_faction = "rethumanoidc"

/obj/random/mob/semirandom_mob_spawner/humanoid/hostile
	mob_faction = "hoshumanoida"
	overwrite_hostility = 1
	mob_hostile = 1
	mob_retaliate = 1

/obj/random/mob/semirandom_mob_spawner/humanoid/hostile/b
	mob_faction = "hoshumanoidb"

/obj/random/mob/semirandom_mob_spawner/humanoid/hostile/c
	mob_faction = "hoshumanoidc"

/obj/random/mob/semirandom_mob_spawner/robot/b
	mob_faction = "robotb"

/obj/random/mob/semirandom_mob_spawner/robot/c
	mob_faction = "robotc"

/obj/random/mob/semirandom_mob_spawner/robot/d
	mob_faction = "robotd"

/obj/random/mob/semirandom_mob_spawner/robot/e
	mob_faction = "robote"

/obj/random/mob/semirandom_mob_spawner/robot/f
	mob_faction = "robotf"

/obj/random/mob/semirandom_mob_spawner/robot/retaliate
	mob_faction = "retrobota"
	overwrite_hostility = 1
	mob_hostile = 0
	mob_retaliate = 1

/obj/random/mob/semirandom_mob_spawner/robot/retaliate/b
	mob_faction = "retrobotb"

/obj/random/mob/semirandom_mob_spawner/robot/retaliate/c
	mob_faction = "retrobotc"

/obj/random/mob/semirandom_mob_spawner/bird/b
	mob_faction = "birdb"

/obj/random/mob/semirandom_mob_spawner/bird/c
	mob_faction = "birdc"

/obj/random/mob/semirandom_mob_spawner/bird/d
	mob_faction = "birdd"

/obj/random/mob/semirandom_mob_spawner/bird/e
	mob_faction = "birde"

/obj/random/mob/semirandom_mob_spawner/bird/f
	mob_faction = "birdf"

/obj/random/mob/semirandom_mob_spawner/fish/b
	mob_faction = "fishb"

/obj/random/mob/semirandom_mob_spawner/fish/c
	mob_faction = "fishc"

/obj/random/mob/semirandom_mob_spawner/fish/d
	mob_faction = "fishd"

/obj/random/mob/semirandom_mob_spawner/fish/e
	mob_faction = "fishe"

/obj/random/mob/semirandom_mob_spawner/fish/f
	mob_faction = "fishf"

/obj/random/mob/semirandom_mob_spawner/vore/b
	mob_faction = "voreb"

/obj/random/mob/semirandom_mob_spawner/vore/c
	mob_faction = "vorec"

/obj/random/mob/semirandom_mob_spawner/vore/d
	mob_faction = "vored"

/obj/random/mob/semirandom_mob_spawner/vore/e
	mob_faction = "voree"

/obj/random/mob/semirandom_mob_spawner/vore/f
	mob_faction = "voref"

/obj/random/mob/semirandom_mob_spawner/vore/passive
	mob_faction = "pasvorea"
	overwrite_hostility = 1
	mob_hostile = 0
	mob_retaliate = 0
	mob_ghostjoin = 25 //25% chance to be ghost joinable

/obj/random/mob/semirandom_mob_spawner/vore/passive/b
	mob_faction = "pasvoreb"

/obj/random/mob/semirandom_mob_spawner/vore/passive/c
	mob_faction = "pasvorec"

/obj/random/mob/semirandom_mob_spawner/vore/retaliate
	mob_faction = "retvorea"
	overwrite_hostility = 1
	mob_hostile = 0
	mob_retaliate = 1
	mob_ghostjoin = 25 //25% chance to be ghost joinable

/obj/random/mob/semirandom_mob_spawner/vore/retaliate/b
	mob_faction = "retvoreb"

/obj/random/mob/semirandom_mob_spawner/vore/retaliate/c
	mob_faction = "retvorec"

/obj/random/mob/semirandom_mob_spawner/vore/hostile
	mob_faction = "hosvorea"
	overwrite_hostility = 1
	mob_hostile = 1
	mob_retaliate = 1

/obj/random/mob/semirandom_mob_spawner/vore/hostile/b
	mob_faction = "hosvoreb"

/obj/random/mob/semirandom_mob_spawner/vore/hostile/c
	mob_faction = "hosvorec"

/obj/random/mob/semirandom_mob_spawner/sus/b
	mob_faction = "susb"

/obj/random/mob/semirandom_mob_spawner/sus/c
	mob_faction = "susc"

/obj/random/mob/semirandom_mob_spawner/sus/d
	mob_faction = "susd"

/obj/random/mob/semirandom_mob_spawner/sus/e
	mob_faction = "suse"

/obj/random/mob/semirandom_mob_spawner/sus/f
	mob_faction = "susf"

/obj/random/mob/semirandom_mob_spawner/mecha/b
	mob_faction = "mechab"

/obj/random/mob/semirandom_mob_spawner/mecha/c
	mob_faction = "mechac"

/obj/random/mob/semirandom_mob_spawner/mecha/d
	mob_faction = "mechad"

/obj/random/mob/semirandom_mob_spawner/mecha/e
	mob_faction = "mechae"

/obj/random/mob/semirandom_mob_spawner/mecha/f
	mob_faction = "mechaf"

/obj/random/mob/semirandom_mob_spawner/mecha/retaliate
	mob_faction = "retmecha"
	overwrite_hostility = 1
	mob_hostile = 0
	mob_retaliate = 1

/obj/random/mob/semirandom_mob_spawner/mecha/retaliate/b
	mob_faction = "retmechb"

/obj/random/mob/semirandom_mob_spawner/mecha/retaliate/c
	mob_faction = "retmechc"
