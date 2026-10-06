/obj/item/projectile/ion
	name = "ion bolt"
	icon_state = "ion"
	fire_sound = SFX_WEAPONS_LASER
	damage = 0
	injury_kind = INJURY_BURN
	nodamage = 1
	light_range = 2
	light_power = 0.5
	light_color = "#55AAFF"
	hud_state = "plasma_blast"
	hud_state_empty = "battery_empty"

	combustion = FALSE
	impact_effect_type = /obj/effect/temp_visual/impact_effect/ion
	hitsound_wall = SFX_WEAPONS_EFFECTS_SEARWALL
	hitsound = SFX_WEAPONS_IONRIFLE

	var/sev1_range = 0
	var/sev2_range = 1
	var/sev3_range = 1
	var/sev4_range = 1

/obj/item/projectile/ion/on_impact(atom/target)
	empulse(target, sev1_range, sev2_range, sev3_range, sev4_range)
	..()

/obj/item/projectile/ion/small
	sev1_range = -1
	sev2_range = 0
	sev3_range = 0
	sev4_range = 1

/obj/item/projectile/ion/pistol
	sev1_range = 0
	sev2_range = 0
	sev3_range = 0
	sev4_range = 0

/obj/item/projectile/bullet/gyro
	name ="explosive bolt"
	icon_state= "bolter"
	damage = 50
	sharp = TRUE
	edge = TRUE
	injury_kind = INJURY_CUT
	hud_state = "rocket_fire"

/obj/item/projectile/bullet/gyro/on_hit(atom/target, blocked = 0)
	explosion(target, -1, 0, 2, 0, 0) // Don't spam admins
	..()

/obj/item/projectile/temp
	name = "freeze beam"
	icon_state = "ice_2"
	fire_sound = SFX_WEAPONS_PULSE3
	damage = 0
	injury_kind = INJURY_BURN
	pass_flags = PASSTABLE | PASSGLASS | PASSGRILLE
	nodamage = 1
	var/target_temperature = 50
	light_range = 2
	light_power = 0.5
	light_color = "#55AAFF"
	impact_effect_type = /obj/effect/temp_visual/impact_effect/monochrome_laser
	hud_state = "water"

	combustion = FALSE

/obj/item/projectile/temp/on_hit(atom/target, blocked = FALSE)
	..()
	if(isliving(target))
		var/mob/living/L = target

		var/protection = null
		var/potential_temperature_delta = null
		var/starting_temperature = L.body_temperature()
		var/new_temperature = starting_temperature

		if(target_temperature < starting_temperature) // Move toward a colder target.
			protection = L.get_cold_protection(target_temperature)
			potential_temperature_delta = 75
			new_temperature = max(new_temperature - potential_temperature_delta, target_temperature)
		else // Make it hot.
			protection = L.get_heat_protection(target_temperature)
			potential_temperature_delta = 200 // Because spacemen temperature needs stupid numbers to actually hurt people.
			new_temperature = min(new_temperature + potential_temperature_delta, target_temperature)

		var/temp_factor = abs(protection - 1)

		new_temperature = starting_temperature + (new_temperature - starting_temperature) * temp_factor
		new_temperature = clamp(new_temperature, min(starting_temperature, target_temperature), max(starting_temperature, target_temperature))
		L.set_bodytemperature(new_temperature)
	// The last metroid has escaped from captivity, the galaxy is no longer safe.
		if(istype(L, /mob/living/simple_mob/vore/alienanimals/space_jellyfish) && target_temperature <= T0C)
			var/mob/living/simple_mob/vore/alienanimals/space_jellyfish/J = L
			J.injure(INJURY_FROSTBITE, 75, source = src)
			J.movement_cooldown *= 2
	return 1

/obj/item/projectile/temp/hot
	name = "heat beam"
	target_temperature = 1000
	hud_state = "flame"

	combustion = TRUE

/obj/item/projectile/meteor
	name = "meteor"
	icon = 'icons/obj/meteor.dmi'
	icon_state = "small"
	damage = 0
	nodamage = 1
	hud_state = "monkey"

/obj/item/projectile/meteor/Bump(atom/A as mob|obj|turf|area)
	if(A == firer)
		forceMove(A.loc)
		return

	if(src)//Do not add to this if() statement, otherwise the meteor won't delete them
		if(A)

			A.ex_act(2)
			play_sfx(src, SFX_EFFECTS_METEORIMPACT)

			for(var/mob/M in range(10, src))
				if(!M.stat && !isAI(M))\
					shake_camera(M, 3, 1)
			spent(src)
			return 1
	else
		return 0

/obj/item/projectile/energy/floramut
	name = "alpha somatoray"
	icon_state = "energy"
	fire_sound = SFX_EFFECTS_STEALTHOFF
	damage = 0
	injury_kind = INJURY_TOXIN
	nodamage = 1
	light_range = 2
	light_power = 0.5
	light_color = "#33CC00"
	impact_effect_type = /obj/effect/temp_visual/impact_effect/monochrome_laser
	var/lasermod = 0
	combustion = FALSE
	hud_state = "electrothermal"

/obj/item/projectile/energy/floramut/on_hit(atom/target, blocked = 0)
	var/mob/living/M = target
	if(ishuman(target))
		var/mob/living/carbon/human/H = M
		if((H.species.flags & IS_PLANT) && (M.nutrition < 500))
			if(prob(15))
				M.apply_effect((rand(30,80)),IRRADIATE)
				M.status_at_least(STAT_WEAKENED, 5)
				for (var/mob/V in viewers(src))
					V.show_message(span_red("[M] writhes in pain as [M.p_their()] vacuoles boil."), 3, span_red("You hear the crunching of leaves."), 2)
			if(prob(35))
				if(prob(80))
					randmutb(M)
					domutcheck(M,null)
				else
					randmutg(M)
					domutcheck(M,null)
				M.UpdateAppearance()
			else
				M.injure(INJURY_BURN, rand(5,15), source = src)
				M.show_message(span_red("The radiation beam singes you!"))
	else if(istype(target, /mob/living/carbon/))
		M.show_message(span_blue("The radiation beam dissipates harmlessly through your body."))
	else
		return 1

/obj/item/projectile/energy/floramut/gene
	name = "gamma somatoray"
	icon_state = "energy2"
	fire_sound = SFX_EFFECTS_STEALTHOFF
	damage = 0
	injury_kind = INJURY_TOXIN
	nodamage = 1
	var/tmp/datum/decl/plantgene/gene_static
	hud_state = "electrothermal"

/obj/item/projectile/energy/florayield
	name = "beta somatoray"
	icon_state = "energy2"
	fire_sound = SFX_EFFECTS_STEALTHOFF
	damage = 0
	injury_kind = INJURY_TOXIN
	nodamage = 1
	light_range = 2
	light_power = 0.5
	light_color = "#FFFFFF"
	impact_effect_type = /obj/effect/temp_visual/impact_effect/monochrome_laser
	var/lasermod = 0
	hud_state = "electrothermal"

/obj/item/projectile/energy/florayield/on_hit(atom/target, blocked = 0)
	var/mob/living/M = target
	if(ishuman(target)) //These rays make plantmen fat.
		var/mob/living/carbon/human/H = M
		if((H.species.flags & IS_PLANT) && (M.nutrition < 500))
			M.adjust_nutrition(30)
	else if (istype(target, /mob/living/carbon/))
		M.show_message(span_blue("The radiation beam dissipates harmlessly through your body."))
	else
		return 1

/obj/item/projectile/energy/floraprune
	name = "delta somatoray"
	icon_state = "energy2"
	fire_sound = SFX_EFFECTS_STEALTHOFF
	damage = 0
	injury_kind = INJURY_TOXIN
	nodamage = 1
	light_range = 2
	light_power = 0.5
	light_color = "#FFFFFF"
	impact_effect_type = /obj/effect/temp_visual/impact_effect/monochrome_laser
	var/lasermod = 0
	hud_state = "electrothermal"

/obj/item/projectile/energy/floraprune/on_hit(atom/target, blocked = 0)
	var/mob/living/M = target
	if(ishuman(target)) //Make plantpeople thin, seeing as we're removing reagents from actual plants
		var/mob/living/carbon/human/H = M
		if((H.species.flags & IS_PLANT) && (M.nutrition > 30))
			M.adjust_nutrition(-30)
	else if (istype(target, /mob/living/carbon/))
		M.show_message(span_blue("The radiation beam dissipates harmlessly through your body."))
	else
		return 1


/obj/item/projectile/beam/mindflayer
	name = "flayer ray"

	combustion = FALSE
	hud_state = "electrothermal"

/obj/item/projectile/beam/mindflayer/on_hit(atom/target, blocked = 0)
	if(ishuman(target))
		var/mob/living/carbon/human/M = target
		M.status_at_least(STAT_CONFUSED, rand(5,8))
	..()

/obj/item/projectile/chameleon
	name = "bullet"
	icon_state = "bullet"
	damage = 1 // stop trying to murderbone with a fake gun dumbass!!!
	embed_chance = 0 // nope
	nodamage = 1
	injury_kind = INJURY_PAIN
	muzzle_type = /obj/effect/projectile/muzzle/bullet
	hud_state = "monkey"

/obj/item/projectile/bola
	name = "bola"
	icon_state = "bola"
	damage = 5
	embed_chance = 0 //Nada.
	injury_kind = INJURY_PAIN
	muzzle_type = null
	hud_state = "monkey"

	combustion = FALSE

/obj/item/projectile/bola/on_hit(atom/target, blocked = 0)
	if(ishuman(target))
		var/mob/living/carbon/human/human_target = target
		for(var/obj/item/clothing/cloth in list(human_target.get_equipped_item(SLOT_ID_SUIT), human_target.get_equipped_item(SLOT_ID_UNIFORM), human_target.get_equipped_item(SLOT_ID_SHOES))) //Check if we have a thick material covering our feet.
			if((cloth.body_parts_covered & FEET) && (cloth.item_flags & THICKMATERIAL))
				..()
				return
		var/obj/item/handcuffs/legcuffs/bola/B = new(src.loc)
		if(!B.place_legcuffs(human_target,firer))
			if(B)
				consume(B)
	..()

/obj/item/projectile/bola/energy
	name = "energy_bola"
	icon_state = "bola_energy"
	damage = 0

/obj/item/projectile/webball
	name = "ball of web"
	icon_state = "bola"
	damage = 10
	embed_chance = 0 //Nada.
	muzzle_type = null
	hud_state = "monkey"
	combustion = FALSE

/obj/item/projectile/webball/on_hit(atom/target, blocked = 0)
	if(isturf(target.loc))
		var/obj/effect/spider/stickyweb/W = locate_within(get_turf(target), /obj/effect/spider/stickyweb)
		if(!W && prob(75))
			visible_message(span_danger("\The [src] splatters a layer of web on \the [target]!"))
			new /obj/effect/spider/stickyweb(target.loc)
	..()

/obj/item/projectile/beam/tungsten
	name = "core of molten tungsten"
	icon_state = "energy"
	fire_sound = SFX_WEAPONS_GAUSS_SHOOT
	pass_flags = PASSTABLE | PASSGRILLE
	damage = 70
	light_range = 4
	light_power = 3
	light_color = "#3300ff"
	hud_state = "alloy_spike"

	muzzle_type = /obj/effect/projectile/muzzle/tungsten
	tracer_type = /obj/effect/projectile/tracer/tungsten
	impact_type = /obj/effect/projectile/impact/tungsten

/obj/item/projectile/beam/tungsten/on_hit(atom/target, blocked = 0)
	if(isliving(target))
		var/mob/living/L = target
		L.apply_body_effect(/datum/body_effect/grievous_wounds, 30 SECONDS)
		if(ishuman(L))
			var/mob/living/carbon/human/H = L

			var/target_armor = H.injury_armor(injury_kind, def_zone)
			var/obj/item/organ/external/target_limb = H.get_organ(def_zone)

			var/armor_special = 0

			if(target_armor >= 60)
				var/turf/T = get_step(H, pick(GLOB.alldirs - src.dir))
				H.throw_at(T, 1, 1, src)
				H.injure(INJURY_BURN, 20, def_zone, src)
				if(target_limb)
					armor_special = 2
					target_limb.fracture()

			else if(target_armor >= 45)
				H.injure(INJURY_BURN, 15, def_zone, src)
				if(target_limb)
					armor_special = 1
					target_limb.dislocate()

			else if(target_armor >= 30)
				H.injure(INJURY_BURN, 10, def_zone, src)
				if(prob(30) && target_limb)
					armor_special = 1
					target_limb.dislocate()

			else if(target_armor >= 15)
				H.injure(INJURY_BURN, 5, def_zone, src)
				if(prob(15) && target_limb)
					armor_special = 1
					target_limb.dislocate()

			if(armor_special > 1)
				target.visible_message(span_cult("\The [src] slams into \the [target]'s [target_limb], reverberating loudly!"))

			else if(armor_special)
				target.visible_message(span_cult("\The [src] slams into \the [target]'s [target_limb] with a low rumble!"))

	..()

/obj/item/projectile/beam/tungsten/on_impact(atom/A)
	if(istype(A,/turf/simulated/shuttle/wall) || istype(A,/turf/simulated/wall) || (ismineralturf(A) && A.density) || istype(A,/obj/mecha) || istype(A,/obj/machinery/door))
		var/blast_dir = src.dir
		A.visible_message(span_danger("\The [A] begins to glow!"))
		after(A, 2 SECONDS, /proc/delayed_blast_beyond, with = list(A, blast_dir))
	..()

/obj/item/projectile/beam/tungsten/Bump(atom/A, forced=0)
	if(istype(A, /obj/structure/window)) //It does not pass through windows. It pulverizes them.
		var/obj/structure/window/W = A
		W.shatter()
		return 0
	..()

/// A tungsten beam's delayed blast, one step past the wall it struck.
/proc/delayed_blast_beyond(atom/A, blast_dir)
	var/blastloc = get_step(A, blast_dir)
	if(blastloc)
		explosion(blastloc, -1, -1, 2, 3)

/// A shared definition/flyweight (never cleared).
/obj/item/projectile/energy/floramut/gene/proc/gene() as /datum/decl/plantgene
	return gene_static
