/obj/item/projectile/energy
	name = "energy"
	icon_state = "spark"
	damage = 0
	injury_kind = INJURY_BURN

	impact_effect_type = /obj/effect/temp_visual/impact_effect
	hitsound_wall = SFX_WEAPONS_EFFECTS_SEARWALL
	hitsound = SFX_WEAPONS_ZAPBANG
	hud_state = "plasma"
	hud_state_empty = "battery_empty"

	var/flash_strength = 10

//releases a burst of light on impact or after travelling a distance
/obj/item/projectile/energy/flash
	name = "chemical shell"
	icon_state = "bullet"
	fire_sound = SFX_WEAPONS_GUNSHOT_PATHETIC
	hitsound_wall = null
	damage = 5
	range = 15 //if the shell hasn't hit anything after travelling this far it just explodes.
	var/flash_range = 0
	var/brightness = 7
	var/light_colour = "#ffffff"
	hud_state = "grenade_dummy"

/obj/item/projectile/energy/flash/on_impact(atom/A)
	var/turf/T = flash_range? src.loc : get_turf(A)
	if(!istype(T)) return

	//blind adjacent people
	for (var/mob/living/carbon/M in viewers(T, flash_range))
		if(M.eyecheck() < 1)
			M.flash_eyes()
			if(ishuman(M))
				var/mob/living/carbon/human/H = M
				var/applied_strength = flash_strength * H.species.flash_mod

				if(applied_strength > 0)
					H.status_at_least(STAT_CONFUSED, applied_strength + 5)
					H.status_at_least(STAT_BLINDED, applied_strength)
					H.status_at_least(STAT_BLURRY, applied_strength + 5)
					H.injure(INJURY_PAIN, 22 * (applied_strength / 5), source = src) // Five flashes to stun.  Bit weaker than melee flashes due to being ranged.

	//snap pop
	play_sfx(src, SFX_EFFECTS_SNAP)
	src.visible_message(span_warning("\The [src] explodes in a bright flash!"))

	fx_sparks(T, 2)

	new /obj/effect/decal/cleanable/ash(src.loc) //always use src.loc so that ash doesn't end up inside windows
	new /obj/effect/effect/smoke/illumination(T, 5, brightness, brightness, light_colour)

//blinds people like the flash round, but can also be used for temporary illumination
/obj/item/projectile/energy/flash/flare
	fire_sound = SFX_WEAPONS_GRENADE_LAUNCHER
	damage = 10
	flash_range = 1
	brightness = 15
	flash_strength = 20
	hud_state = "grenade_dummy"

/obj/item/projectile/energy/flash/flare/on_impact(atom/A)
	light_colour = pick("#e58775", "#ffffff", "#90ff90", "#a09030")

	..() //initial flash

	//residual illumination
	new /obj/effect/effect/smoke/illumination(loc, rand(190,240) SECONDS, 8, 3, light_colour) //same lighting power as flare

/obj/item/projectile/energy/electrode
	name = "electrode"
	icon_state = "spark"
	fire_sound = SFX_WEAPONS_GUNSHOT2
	taser_effect = 1
	agony = 40
	light_range = 2
	light_power = 0.5
	light_color = "#FFFFFF"
	hud_state = "taser"
	//Damage will be handled on the MOB side, to prevent window shattering.

/obj/item/projectile/energy/electrode/strong
	agony = 55
	hud_state = "taser"

/obj/item/projectile/energy/electrode/stunshot
	name = "stunshot"
	damage = 5
	agony = 80
	hud_state = "taser"

/obj/item/projectile/energy/electrode/stunshot/strong
	name = "stunshot"
	icon_state = "bullet"
	damage = 10
	taser_effect = 1
	agony = 100
	hud_state = "taser"

/obj/item/projectile/energy/declone
	name = "declone"
	icon_state = "declone"
	fire_sound = SFX_WEAPONS_PULSE3
	nodamage = 1
	injury_kind = INJURY_CELLULAR
	irradiate = 40
	light_range = 2
	light_power = 0.5
	light_color = "#33CC00"
	impact_effect_type = /obj/effect/temp_visual/impact_effect/monochrome_laser

	combustion = FALSE
	hud_state = "plasma_pistol"

/obj/item/projectile/energy/excavate
	name = "kinetic blast"
	icon_state = "kinetic_blast"
	fire_sound = SFX_WEAPONS_PULSE3
	injury_kind = INJURY_BLUNT
	damage = 30
	armor_penetration = 60
	excavation_amount = 200

	vacuum_traversal = 0
	combustion = FALSE
	hud_state = "plasma_blast"

/obj/item/projectile/energy/excavate/weak
	damage = 15
	excavation_amount = 100

/obj/item/projectile/energy/dart
	name = "dart"
	icon_state = "toxin"
	damage = 5
	injury_kind = INJURY_TOXIN
	agony = 120
	hud_state = "pistol_tranq"

	combustion = FALSE

/obj/item/projectile/energy/bolt
	name = "bolt"
	icon_state = "cbbolt"
	damage = 10
	injury_kind = INJURY_TOXIN
	agony = 40
	stutter = 10
	hud_state = "electrothermal"

/obj/item/projectile/energy/bolt/large
	name = "largebolt"
	damage = 20
	hud_state = "electrothermal"

/obj/item/projectile/energy/bow
	name = "engergy bolt"
	icon_state = "cbbolt"
	damage = 20
	hud_state = "electrothermal"

/obj/item/projectile/energy/bow/heavy
	damage = 30
	icon_state = "cbbolt"
	hud_state = "electrothermal"

/obj/item/projectile/energy/bow/stun
	name = "stun bolt"
	agony = 30
	hud_state = "electrothermal"

/obj/item/projectile/energy/acid //Slightly up-gunned (Read: The thing does agony and checks bio resist) variant of the simple alien mob's projectile, for queens and sentinels.
	name = "acidic spit"
	icon_state = "neurotoxin"
	damage = 30
	agony = 10
	armor_penetration = 25	// It's acid
	hitsound_wall = SFX_WEAPONS_EFFECTS_ALIEN_SPIT_WALL
	hitsound = SFX_WEAPONS_EFFECTS_ALIEN_SPIT_WALL
	hud_state = "electrothermal"

	combustion = FALSE

/obj/item/projectile/energy/neurotoxin
	name = "neurotoxic spit"
	icon_state = "neurotoxin"
	damage = 0
	injury_kind = INJURY_CORROSIVE
	agony = 60 // lowered agony damage
	armor_penetration = 25	// It's acid-based
	hitsound_wall = SFX_WEAPONS_EFFECTS_ALIEN_SPIT_WALL
	hitsound = SFX_WEAPONS_EFFECTS_ALIEN_SPIT_WALL
	hud_state = "electrothermal"

	combustion = FALSE

/obj/item/projectile/energy/neurotoxin/toxic //New alien mob projectile to match the player-variant's projectiles.
	name = "neurotoxic spit"
	icon_state = "neurotoxin"
	damage = 20
	agony = 20
	hud_state = "electrothermal"
	armor_penetration = 25	// It's acid-based

/obj/item/projectile/energy/phoron
	name = "phoron bolt"
	icon_state = "energy"
	fire_sound = SFX_EFFECTS_STEALTHOFF
	damage = 20
	injury_kind = INJURY_TOXIN
	irradiate = 20
	light_range = 2
	light_power = 0.5
	light_color = "#33CC00"
	impact_effect_type = /obj/effect/temp_visual/impact_effect/monochrome_laser
	hud_state = "plasma_rifle"

	combustion = FALSE

/obj/item/projectile/energy/plasmastun
	name = "plasma pulse"
	icon_state = "plasma_stun"
	fire_sound = SFX_WEAPONS_BLASTER
	armor_penetration = 10
	range = 4
	damage = 5
	agony = 55
	vacuum_traversal = 0	//Projectile disappears in empty space
	hud_state = "plasma_rifle_blast"

/obj/item/projectile/energy/plasmastun/proc/bang(mob/living/carbon/M)

	to_chat(M, span_danger("You hear a loud roar."))
	play_sfx(src, SFX_EFFECTS_BANG)
	var/ear_safety = 0
	ear_safety = M.get_ear_protection()
	if(ear_safety == 1)
		M.status_at_least(STAT_CONFUSED, 150)
	else if (ear_safety > 1)
		M.status_at_least(STAT_CONFUSED, 30)
	else if (!ear_safety)
		M.status_at_least(STAT_STUNNED, 10)
		M.status_at_least(STAT_WEAKENED, 2)
		M.set_ear_damage(M.ear_damage + (rand(1, 10)))
		M.status_at_least(STAT_DEAFENED, 15)
		M.deaf_loop.start() // Ear Ringing/Deafness
	if (M.ear_damage >= 15)
		to_chat(M, span_danger("Your ears start to ring badly!"))
		if (prob(M.ear_damage - 5))
			to_chat(M, span_danger("You can't hear anything!"))
			M.set_sdisabilities(M.sdisabilities | (DEAF))
			M.deaf_loop.start() // Ear Ringing/Deafness
	else
		if (M.ear_damage >= 5)
			to_chat(M, span_danger("Your ears start to ring!"))
	M.update_icons() //Just to apply matrix transform for laying asap

/obj/item/projectile/energy/plasmastun/on_hit(atom/target)
	bang(target)
	. = ..()

/obj/item/projectile/energy/blue_pellet
	name = "suppressive pellet"
	icon_state = "blue_pellet"
	fire_sound = SFX_WEAPONS_LASER5
	damage = 5
	armor_penetration = 75
	pass_flags = PASSTABLE | PASSGLASS | PASSGRILLE
	light_color = "#00AAFF"

	embed_chance = 0
	muzzle_type = /obj/effect/projectile/muzzle/pulse
	impact_effect_type = /obj/effect/temp_visual/impact_effect/monochrome_laser
	hud_state = "plasma_sphere"

/* ChompEdit, moving over to energy_ch.dm
/obj/item/projectile/energy/phase
	name = "phase wave"
	icon_state = "phase"
	range = 13 // This range was still awful
	damage = 5
	mob_bonus_damage = 45
	hud_state = "laser_heat"

/obj/item/projectile/energy/phase/light
	range = 4
	hud_state = "laser_heat"

/obj/item/projectile/energy/phase/heavy
	range = 8
	hud_state = "laser_heat"

/obj/item/projectile/energy/phase/heavy/cannon
	range = 20 // This range was mediocre, but not worth a cannon.
	damage = 15
	hud_state = "laser_heat"
*/

/obj/item/projectile/energy/electrode/strong
	agony = 70
	hud_state = "taser"

/obj/item/projectile/energy
	flash_strength = 10
	hud_state = "taser"

/obj/item/projectile/energy/flash
	flash_range = 1
	hud_state = "grenade_dummy"

/obj/item/projectile/energy/flash/strong
	name = "chemical shell"
	icon_state = "bullet"
	damage = 10
	range = 15 //if the shell hasn't hit anything after travelling this far it just explodes.
	flash_strength = 15
	brightness = 15
	hud_state = "grenade_dummy"

/obj/item/projectile/energy/flash/flare
	flash_range = 2
	hud_state = "grenade_dummy"

/obj/item/projectile/energy/anomaly
	name = "anomaly emitter projectile"
	light_color = "#be008f"
	icon_state = "purple_laser"
	damage = 5
	speed = 1.6
	var/particle_type

CAPABILITIES(/obj/item/projectile/energy/anomaly)
	param(nameof(particle_type), pos = 1)

/obj/item/projectile/energy/phase/bolt
	range = 4
	mob_bonus_damage = 15	// 30 total on animals
	icon_state = "cbbolt"
	hud_state = "taser"

/obj/item/projectile/energy/phase/bolt/heavy
	range = 4
	mob_bonus_damage = 25	// 20 total on animals
	hud_state = "taser"

/obj/item/projectile/energy/plasma/vepr
	name = "plasma bolt"
	icon = 'icons/obj/projectiles_ch.dmi'
	icon_state = "vepr"
	fire_sound = SFX_WEAPONS_SERDY_VEPR
	damage = 30
	armor_penetration = 10
	muzzle_type = /obj/effect/projectile/muzzle/vepr
	impact_effect_type = /obj/effect/temp_visual/impact_effect
	hitsound_wall = SFX_WEAPONS_EFFECTS_SEARWALL
	hitsound = SFX_WEAPONS_SEAR
	hud_state = "laser_overcharge"

/obj/item/projectile/energy/phase
	name = "phase wave"
	icon_state = "phase"
	fire_sound = SFX_WEAPONS_PHASE_NEW_PHASECARBINE // New sounds.
	range = 13
	damage = 5
	mob_bonus_damage = 45
	armor_penetration = -35
	hud_state = "laser_heat"

/obj/item/projectile/energy/phase/light
	fire_sound = SFX_WEAPONS_PHASE_NEW_PHASEPISTOL // New sounds.
	range = 11
	mob_bonus_damage = 35
	armor_penetration = -50
	hud_state = "laser_heat"

/obj/item/projectile/energy/phase/heavy
	fire_sound = SFX_WEAPONS_PHASE_NEW_PHASERIFLE // New sounds.
	range = 16 // This range was not great
	damage = 10
	mob_bonus_damage = 50
	armor_penetration = -25
	hud_state = "laser_heat"

/obj/item/projectile/energy/phase/heavy/cannon
	fire_sound = SFX_WEAPONS_PHASE_NEW_PHASECANNON // New sounds.
	range = 20 // This range was mediocre, but not worth a cannon.
	damage = 15
	mob_bonus_damage = 60
	armor_penetration = -20
	hud_state = "laser_heat"
