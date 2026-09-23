/mob/living/simple_mob/animal/space/alien
	name = "alien hunter"
	desc = "Hiss!"
	icon = 'icons/mob/alien.dmi'
	icon_state = "alienh_running"
	icon_living = "alienh_running"
	icon_dead = "alien_l"
	icon_gib = "syndicate_gib"
	icon_rest = "alienh_sleep"

	faction = FACTION_XENO

	mob_class = MOB_CLASS_ABERRATION

	response_help = "pokes"
	response_disarm = "shoves"
	response_harm = "hits"

	endurance = 100
	see_in_dark = 7

	harm_intent_damage = 5
	melee_damage_lower = 25
	melee_damage_upper = 25
	attack_armor_pen = 15	//It's a freaking alien.
	attack_injury_kind = INJURY_CUT

	attacktext = list("slashed")
	attack_sound = 'sound/weapons/bladeslice.ogg'

	meat_type = /obj/item/reagent_containers/food/snacks/xenomeat
	meat_amount = 5

	can_be_drop_prey = FALSE

/mob/living/simple_mob/animal/space/alien/drone
	name = "alien drone"
	icon_state = "aliend_running"
	icon_living = "aliend_running"
	icon_dead = "aliend_l"
	icon_rest = "aliend_sleep"
	melee_damage_lower = 15
	melee_damage_upper = 15

/mob/living/simple_mob/animal/space/alien/sentinel
	name = "alien sentinel"
	icon_state = "aliens_running"
	icon_living = "aliens_running"
	icon_dead = "aliens_l"
	icon_rest = "aliens_sleep"
	melee_damage_lower = 15
	melee_damage_upper = 15
	projectiletype = /obj/item/projectile/energy/neurotoxin/toxic
	projectilesound = 'sound/weapons/pierce.ogg'

/mob/living/simple_mob/animal/space/alien/sentinel/praetorian
	name = "alien praetorian"
	icon = 'icons/mob/64x64.dmi'
	icon_state = "prat_s"
	icon_living = "prat_s"
	icon_dead = "prat_dead"
	icon_rest = "prat_sleep"
	endurance = 200

	pixel_x = -16
	old_x = -16
	icon_expected_width = 64
	icon_expected_height = 64
	meat_amount = 8

/mob/living/simple_mob/animal/space/alien/queen
	name = "alien queen"
	icon_state = "alienq_running"
	icon_living = "alienq_running"
	icon_dead = "alienq_l"
	icon_rest = "alienq_sleep"
	endurance = 250
	melee_damage_lower = 15
	melee_damage_upper = 15
	projectiletype = /obj/item/projectile/energy/neurotoxin/toxic
	projectilesound = 'sound/weapons/pierce.ogg'


	movement_cooldown = 3

/mob/living/simple_mob/animal/space/alien/queen/empress
	name = "alien empress"
	icon = 'icons/mob/64x64.dmi'
	icon_state = "queen_s"
	icon_living = "queen_s"
	icon_dead = "queen_dead"
	icon_rest = "queen_sleep"
	endurance = 400
	meat_amount = 15

	pixel_x = -16
	old_x = -16
	icon_expected_width = 64
	icon_expected_height = 64

/mob/living/simple_mob/animal/space/alien/queen/empress/mother
	name = "alien mother"
	icon = 'icons/mob/96x96.dmi'
	icon_state = "empress_s"
	icon_living = "empress_s"
	icon_dead = "empress_dead"
	icon_rest = "empress_rest"
	endurance = 600
	meat_amount = 40
	melee_damage_lower = 15
	melee_damage_upper = 25

	pixel_x = -32
	old_x = -32
	icon_expected_width = 96
	icon_expected_height = 96

/mob/living/simple_mob/animal/space/alien/death()
	..()
	visible_message("[src] lets out a waning guttural screech, green blood bubbling from its maw...")
	playsound(src, 'sound/voice/hiss6.ogg', 100, 1)


// === merged from alien_chomp.dm during hard-fork de-suffix (verified no override-order change) ===

//what are this things?
/mob/living/simple_mob/animal/space/alien/sentinel/praetorian/echo
	name = "alien Echopraetorian"
	color = "#424242"
	endurance = 300
	needs_reload = 1
	projectiletype = /obj/item/projectile/sonic/strong
	reload_time = 150 SECONDS

/mob/living/simple_mob/animal/space/alien/sentinel/praetorian/ion
	name = "alien Ionic praetorian"
	color = "#004cff"
	armor_spec = "bullet=25;bio=100;rad=100"
	endurance = 350
	needs_reload = 1
	projectiletype = /obj/item/projectile/arc/emp_blast
	reload_time = 150 SECONDS
	reload_max = 3
	size_multiplier = 1.5

/mob/living/simple_mob/animal/space/alien/sentinel/praetorian/blaze
	name = "alien blazing praetorian"
	color = "Red"
	armor_spec = "laser=25;bio=100;rad=100"
	endurance = 450
	needs_reload = 1
	projectiletype = /obj/item/projectile/energy/fireball
	reload_max = 3
	reload_time = 200

/mob/living/simple_mob/animal/space/alien/sentinel/praetorian/splat
	name = "alien splattetorian"
	color = "#a604b8"
	needs_reload = 1
	projectiletype = /obj/item/projectile/energy/blob/acid/splattering
	reload_max = 5
	reload_time = 150
	size_multiplier = 0.75

/mob/living/simple_mob/animal/space/alien/sentinel/praetorian/tank
	name = "alien Tankerling"
	armor_spec = "melee=-25;bullet=20;laser=20"
	base_attack_cooldown = 25
	color = "#ff8214"
	endurance = 700
	melee_damage_lower = 25
	melee_damage_upper = 35
	movement_cooldown = 10
	movement_shake_radius = 7
	movement_sound = 'sound/weapons/heavysmash.ogg'
	projectiletype = null
	size_multiplier = 2

/mob/living/simple_mob/animal/space/alien/sentinel/praetorian/acid
	projectiletype = /obj/item/projectile/energy/acid

/mob/living/simple_mob/animal/space/alien/queen/empress/star
	name = "alien Staticlisk"
	base_attack_cooldown = 15
	color = "#38b9ff"
	endurance = 500
	armor_spec = "melee=-20;bullet=20;laser=10"
	melee_damage_lower = 25
	melee_damage_upper = 30
	movement_cooldown = 12
	movement_shake_radius = 7
	needs_reload = 1
	projectilesound = null
	projectiletype = /obj/item/projectile/beam/chain_lightning/lesser
	reload_max = 3
	reload_time = 200
	size_multiplier = 1.5

/mob/living/simple_mob/animal/space/alien/queen/empress/tank
	name = "alien tankerlisk"
	base_attack_cooldown = 25
	color = "#4a4a4a"
	endurance = 1250
	armor_spec = "melee=-20;bullet=20;laser=10"
	melee_damage_lower = 25
	melee_damage_upper = 30
	movement_cooldown = 12
	movement_shake_radius = 7
	needs_reload = 1
	projectilesound = null
	projectiletype = null
	size_multiplier = 3

/mob/living/simple_mob/animal/space/alien/sentinel/electro
	name = "alien Electrosentinel"
	color = "#ccff4a"
	endurance = 200
	armor_spec = "bullet=10;laser=10"
	needs_reload = 1
	projectiletype = /obj/item/projectile/beam/stun/electric_spider
	reload_max = 5
	reload_time = 150
	size_multiplier = 1.5

/mob/living/simple_mob/animal/space/alien/sentinel/pyro
	name = "alien Pyrosentinel"
	armor_spec = "laser=15;bio=100;rad=100"
	base_attack_cooldown = 15
	color = "#ff7373"
	endurance = 250
	needs_reload = 1
	projectiletype = /obj/item/projectile/bullet/incendiary/dragonflame
	reload_max = 2
	reload_time = 150

/mob/living/simple_mob/animal/space/alien/sentinel/cyro
	name = "alien cryosentinel"
	armor_spec = "bullet=15;bio=100;rad=100"
	color = "#4f83ff"
	endurance = 200
	needs_reload = 1
	projectiletype = /obj/item/projectile/energy/blob/freezing/splattering
	reload_max = 3
	reload_time = 100
	size_multiplier = 1.5

/mob/living/simple_mob/animal/space/alien/sentinel/acid
	projectiletype = /obj/item/projectile/energy/acid

/mob/living/simple_mob/animal/space/alien/tanky
	endurance = 200

/mob/living/simple_mob/animal/space/alien/hunterling
	name = "alien hunterling"
	attack_armor_pen = 1
	base_attack_cooldown = 2
	color = "#1cbdff"
	force_max_speed = 1
	endurance = 15
	melee_damage_lower = 1
	melee_damage_upper = 3
	size_multiplier = 0.5

/mob/living/simple_mob/animal/space/alien/hunterlisk
	name = "alien hunterlisk"
	base_attack_cooldown = 15
	color = "#575757"
	endurance = 150
	melee_damage_upper = 35
	movement_cooldown = 3
	size_multiplier = 1.25

/mob/living/simple_mob/animal/space/alien/queen/empress/mother/big
	needs_reload = 1
	projectiletype = /obj/item/projectile/energy/blob/toxic/splattering
	reload_max = 5
	reload_time = 150
	size_multiplier = 2
