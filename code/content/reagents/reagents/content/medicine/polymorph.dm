/datum/reagent/polymorph
	name = REAGENT_POLYMORPH
	id = REAGENT_ID_POLYMORPH
	description = "A chemical that instantly transforms the consumer into another creature."
	taste_description = "luck"
	reagent_state = LIQUID
	color = "#a754de"
	scannable = 1
	var/tf_type = /mob/living/simple_mob/animal/passive/mouse
	var/tf_possible_types = list(
		"mouse" = /mob/living/simple_mob/animal/passive/mouse,
		"rat" = /mob/living/simple_mob/animal/passive/mouse/rat,
		"giant rat" = /mob/living/simple_mob/vore/aggressive/rat,
		"dust jumper" = /mob/living/simple_mob/vore/alienanimals/dustjumper,
		"woof" = /mob/living/simple_mob/vore/woof,
		"corgi" = /mob/living/simple_mob/animal/passive/dog/corgi,
		"cat" = /mob/living/simple_mob/animal/passive/cat,
		"chicken" = /mob/living/simple_mob/animal/passive/chicken,
		"cow" = /mob/living/simple_mob/animal/passive/cow,
		"lizard" = /mob/living/simple_mob/animal/passive/lizard,
		"rabbit" = /mob/living/simple_mob/vore/rabbit,
		"fox" = /mob/living/simple_mob/animal/passive/fox,
		"fennec" = /mob/living/simple_mob/vore/fennec,
		"cute fennec" = /mob/living/simple_mob/animal/passive/fennec,
		"fennix" = /mob/living/simple_mob/vore/fennix,
		"red panda" = /mob/living/simple_mob/vore/redpanda,
		"opossum" = /mob/living/simple_mob/animal/passive/opossum,
		"horse" = /mob/living/simple_mob/vore/horse,
		"goose" = /mob/living/simple_mob/animal/space/goose,
		"sheep" = /mob/living/simple_mob/vore/sheep,
		"space bumblebee" = /mob/living/simple_mob/vore/bee,
		"space bear" = /mob/living/simple_mob/animal/space/bear,
		"voracious lizard" = /mob/living/simple_mob/vore/aggressive/dino,
		"giant frog" = /mob/living/simple_mob/vore/aggressive/frog,
		"jelly blob" = /mob/living/simple_mob/vore/jelly,
		"wolf" = /mob/living/simple_mob/vore/wolf,
		"direwolf" = /mob/living/simple_mob/vore/wolf/direwolf,
		"great wolf" = /mob/living/simple_mob/vore/greatwolf,
		"sect queen" = /mob/living/simple_mob/vore/sect_queen,
		"sect drone" = /mob/living/simple_mob/vore/sect_drone,
		"panther" = /mob/living/simple_mob/vore/aggressive/panther,
		"giant snake" = /mob/living/simple_mob/vore/aggressive/giant_snake,
		"deathclaw" = /mob/living/simple_mob/vore/aggressive/deathclaw,
		"otie" = /mob/living/simple_mob/vore/otie,
		"mutated otie" =/mob/living/simple_mob/vore/otie/feral,
		"red otie" = /mob/living/simple_mob/vore/otie/red,
		"defanged xenomorph" = /mob/living/simple_mob/vore/xeno_defanged,
		"catslug" = /mob/living/simple_mob/vore/alienanimals/catslug,
		"monkey" = /mob/living/carbon/human/monkey,
		"wolpin" = /mob/living/carbon/human/wolpin,
		"sparra" = /mob/living/carbon/human/sparram,
		"saru" = /mob/living/carbon/human/sergallingm,
		"sobaka" = /mob/living/carbon/human/sharkm,
		"farwa" = /mob/living/carbon/human/farwa,
		"neaera" = /mob/living/carbon/human/neaera,
		"stok" = /mob/living/carbon/human/stok,
		"weretiger" = /mob/living/simple_mob/vore/weretiger,
		"dragon" = /mob/living/simple_mob/vore/bigdragon/friendly,
		"leopardmander" = /mob/living/simple_mob/vore/leopardmander
		)
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED // bonus
	industrial_use = REFINERYEXPORT_REASON_WEAPONS

/datum/reagent/polymorph/affect_blood(mob/living/carbon/target, removed)
	var/mob/living/M = target
	if(!istype(M))
		return
	if(!M.vore_prefs.allow_spontaneous_tf)
		return
	if(M.tf_mob_holder)
		M.revert_mob_tf()
		return
	else
		if(M.stat == DEAD)	//We can let it undo the TF, because the person will be dead, but otherwise things get weird.
			return
		var/mob/living/new_mob = spawn_mob(M)

		M.tf_into(new_mob)
	target.bloodstr.clear_reagents() //Got to clear all reagents to make sure mobs don't keep spawning.
	target.ingested.clear_reagents()
	target.touching.clear_reagents()

/datum/reagent/polymorph/proc/spawn_mob(mob/living/target)
	var/choice = pick(tf_possible_types)
	tf_type = tf_possible_types[choice]
	if(!ispath(tf_type))
		return
	var/new_mob = new tf_type(get_turf(target))
	return new_mob
