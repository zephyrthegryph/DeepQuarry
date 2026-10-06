/datum/category_item/catalogue/fauna/frog
	name = "Wildlife - Giant Frog"
	desc = "Classification: Anura Gigantus\
	<br><br>\
	A frog is any member of a diverse and largely carnivorous group of short-bodied, tailless amphibians composing \
	the order Anura. This specific species - Anura gigantus - is a mutated form of frogs, largely due to exposure to mutagen chemicals. \
	These giant frogs are descendants from scientific frogs that were used for study during the great Sol Expansion Period. \
	Modern day giant frogs have reverted to a more feral state compared to their original ancestors and are hostile \
	towards humans and other small wildlife - hunting them for food.\
	<br>\
	The particular breed of frog that was originally used in the scientific experiments were known as explosive breeders.\
	With explosive breeders, mature adult frogs arrive at breeding sites in response to certain trigger factors such as rainfall \
	occurring in an arid area. In these frogs, mating and spawning take place promptly and the speed of larval growth is rapid in \
	order to make use of the ephemeral pools before they dry up. Because of this, the frog population is through the roof and has \
	become a major issue for various colonies and stations.\
	<br>\
	These animals, are considered an invasive species, and thus hunters are encouraged to hunt them."
	value = CATALOGUER_REWARD_TRIVIAL

/mob/living/simple_mob/vore/aggressive/frog
	name = "giant frog"
	desc = "You've heard of having a frog in your throat, now get ready for the reverse."
	tt_desc = "Anura Gigantus"
	catalogue_data = list(/datum/category_item/catalogue/fauna/frog)

	icon_dead = "frog-dead"
	icon_living = "frog"
	icon_state = "frog"
	icon = 'icons/mob/vore.dmi'

	movement_cooldown = 0.5 //fast as fucc boie.
	can_be_drop_pred = 1 //They can tongue vore.

	meat_amount = 4
	meat_type = /obj/item/reagent_containers/food/snacks/meat

	harm_intent_damage = 5
	melee_damage_lower = 5
	melee_damage_upper = 12


	special_attack_min_range = 1
	special_attack_max_range = 5
	special_attack_cooldown = 100

	can_be_drop_prey = FALSE
	allow_mind_transfer = TRUE

CAPABILITIES(/mob/living/simple_mob/vore/aggressive/frog)
	rolls(nameof(rare), PROC_REF(roll_rare))
	rolls(nameof(name), PROC_REF(roll_rare_name), from = list(nameof(rare)))
	rolls(nameof(desc), PROC_REF(roll_rare_desc), from = list(nameof(rare)))

/// A one-in-a-million frog (rolled).
/mob/living/simple_mob/vore/aggressive/frog/var/rare = FALSE

/// Rolled before init (rolls()): one frog in a million.
/mob/living/simple_mob/vore/aggressive/frog/proc/roll_rare(datum/roller/R)
	return R.number(1, 1000000) == 1

/mob/living/simple_mob/vore/aggressive/frog/proc/roll_rare_name(datum/roller/R)
	return rare ? "rare Pepe" : name

/mob/living/simple_mob/vore/aggressive/frog/proc/roll_rare_desc(datum/roller/R)
	return rare ? "You found a rare Pepe. Screenshot for good luck." : desc

/mob/living/simple_mob/vore/aggressive/frog/do_special_attack(atom/A, stance)
	ai_busy_begin()
	do_windup_animation(A, 20)
	after(src, 2 SECONDS, PROC_REF(chargeend), with = list(A))

/mob/living/simple_mob/vore/aggressive/frog/proc/chargeend(atom/A)
	if(stat) //you are dead
		ai_busy_end()
		return
	play_sfx(src, SFX_VORE_SUNESOUND_PRED_SCHLORP)
	var/obj/item/projectile/beam/appendage/appendage_attack = new /obj/item/projectile/beam/appendage(get_turf(loc))
	appendage_attack.old_style_target(A, src)
	appendage_attack.launch_projectile(A, BP_TORSO, src)
	ai_busy_end()
// Activate Noms!
/mob/living/simple_mob/vore/aggressive/frog
	vore_active = 1
	vore_pounce_chance = 50
	vore_icons = SA_ICON_LIVING

/mob/living/simple_mob/vore/aggressive/frog/space
	name = "space frog"

	//Space frog can hold its breath or whatever
	min_oxy = 0
	max_oxy = 0
	min_tox = 0
	max_tox = 0
	min_co2 = 0
	max_co2 = 0
	min_n2 = 0
	max_n2 = 0
	minbodytemp = 0
