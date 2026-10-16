/obj/item/projectile/beam
	name = "laser"
	icon_state = "laser"
	fire_sound = SFX_WEAPONS_LASER
	pass_flags = PASSTABLE | PASSGLASS | PASSGRILLE
	damage = 40
	injury_kind = INJURY_BURN
	eyeblur = 4
	var/frequency = 1
	hitscan = 1
	embed_chance = 0
	invisibility = INVISIBILITY_BADMIN	//beam projectiles are invisible as they are rendered by the effect engine
	hitsound_wall = SFX_WEAPONS_EFFECTS_SEARWALL

	muzzle_type = /obj/effect/projectile/muzzle/laser
	tracer_type = /obj/effect/projectile/tracer/laser
	impact_type = /obj/effect/projectile/impact/laser

	hud_state = "laser"
	hud_state_empty = "battery_empty"

CAPABILITIES(/obj/item/projectile/beam)
	configure(light_glow(range = 2, power = 0.5, color = "#FF0D00"))
	configure(item_sounds(hit = SFX_WEAPONS_SEAR))

/obj/item/projectile/beam/practice
	name = "laser"
	icon_state = "laser"
	damage = 0
	excavation_amount = 0
	eyeblur = 2
	hud_state = "laser"

/obj/item/projectile/beam/weaklaser
	name = "weak laser"
	icon_state = "laser"
	damage = 15
	hud_state = "laser"

/obj/item/projectile/beam/weaklaser/blue
	icon_state = "bluelaser"
	hud_state = "laser_disabler"

	muzzle_type = /obj/effect/projectile/muzzle/laser_blue
	tracer_type = /obj/effect/projectile/tracer/laser_blue
	impact_type = /obj/effect/projectile/impact/laser_blue

CAPABILITIES(/obj/item/projectile/beam/weaklaser/blue)
	configure(light_glow(color = "#0066FF"))

/obj/item/projectile/beam/weaklaser/ion
	injury_kind = INJURY_ELECTRIC
	emp_on_hit = TRUE
	muzzle_type = /obj/effect/projectile/muzzle/laser_em
	tracer_type = /obj/effect/projectile/tracer/laser_em
	impact_type = /obj/effect/projectile/impact/laser_em

CAPABILITIES(/obj/item/projectile/beam/weaklaser/ion)
	configure(light_glow(color = "#00CCFF"))

/obj/item/projectile/beam/smalllaser
	damage = 25
	hud_state = "laser"

/obj/item/projectile/beam/smalllaser/ion
	injury_kind = INJURY_ELECTRIC
	emp_on_hit = TRUE
	muzzle_type = /obj/effect/projectile/muzzle/laser_em
	tracer_type = /obj/effect/projectile/tracer/laser_em
	impact_type = /obj/effect/projectile/impact/laser_em

CAPABILITIES(/obj/item/projectile/beam/smalllaser/ion)
	configure(light_glow(color = "#00CCFF"))

/obj/item/projectile/beam/burstlaser
	damage = 30
	hud_state = "laser"

CAPABILITIES(/obj/item/projectile/beam/burstlaser)
	configure(item_combat(armor_penetration = 10))

/obj/item/projectile/beam/burstlaser/ion
	injury_kind = INJURY_ELECTRIC
	emp_on_hit = TRUE
	muzzle_type = /obj/effect/projectile/muzzle/laser_em
	tracer_type = /obj/effect/projectile/tracer/laser_em
	impact_type = /obj/effect/projectile/impact/laser_em

CAPABILITIES(/obj/item/projectile/beam/burstlaser/ion)
	configure(light_glow(color = "#00CCFF"))

/obj/item/projectile/beam/midlaser
	damage = 40
	hud_state = "laser"

CAPABILITIES(/obj/item/projectile/beam/midlaser)
	configure(item_combat(armor_penetration = 10))

/obj/item/projectile/beam/midlaser/ion
	injury_kind = INJURY_ELECTRIC
	emp_on_hit = TRUE
	muzzle_type = /obj/effect/projectile/muzzle/laser_em
	tracer_type = /obj/effect/projectile/tracer/laser_em
	impact_type = /obj/effect/projectile/impact/laser_em

CAPABILITIES(/obj/item/projectile/beam/midlaser/ion)
	configure(light_glow(color = "#00CCFF"))

/obj/item/projectile/beam/mininglaser
	name = "pulsating laser"
	damage = 10
	fire_sound = SFX_WEAPONS_ELUGER

	excavation_amount = 100

	muzzle_type = /obj/effect/projectile/muzzle/emitter
	tracer_type = /obj/effect/projectile/tracer/emitter
	impact_type = /obj/effect/projectile/impact/emitter

CAPABILITIES(/obj/item/projectile/beam/mininglaser)
	configure(item_combat(armor_penetration = 20))

/obj/item/projectile/beam/heavylaser
	name = "heavy laser"
	icon_state = "heavylaser"
	fire_sound = SFX_WEAPONS_LASERCANNONFIRE
	damage = 60

	muzzle_type = /obj/effect/projectile/muzzle/laser_heavy
	tracer_type = /obj/effect/projectile/tracer/laser_heavy
	impact_type = /obj/effect/projectile/impact/laser_heavy
	hud_state = "laser_overcharge"

CAPABILITIES(/obj/item/projectile/beam/heavylaser)
	configure(light_glow(range = 3, power = 1, color = "#FF0D00"))
	configure(item_combat(armor_penetration = 30))

/obj/item/projectile/beam/heavylaser/fakeemitter
	name = "emitter beam"
	icon_state = "emitter"
	fire_sound = SFX_WEAPONS_EMITTER
	excavation_amount = 140	// 2 shots to dig a standard rock turf. Superior due to being a mounted tool beam, to make it actually viable.
	hud_state = "laser_overcharge"

	muzzle_type = /obj/effect/projectile/muzzle/emitter
	tracer_type = /obj/effect/projectile/tracer/emitter
	impact_type = /obj/effect/projectile/impact/emitter

CAPABILITIES(/obj/item/projectile/beam/heavylaser/fakeemitter)
	configure(light_glow(color = "#00CC33"))

/obj/item/projectile/beam/heavylaser/ion
	injury_kind = INJURY_ELECTRIC
	emp_on_hit = TRUE
	muzzle_type = /obj/effect/projectile/muzzle/laser_em
	tracer_type = /obj/effect/projectile/tracer/laser_em
	impact_type = /obj/effect/projectile/impact/laser_em

CAPABILITIES(/obj/item/projectile/beam/heavylaser/ion)
	configure(light_glow(color = "#00CCFF"))

/obj/item/projectile/beam/heavylaser/cannon
	damage = 80
	hud_state = "laser_overcharge"

CAPABILITIES(/obj/item/projectile/beam/heavylaser/cannon)
	configure(light_glow(color = "#FF0D00"))
	configure(light_glow(color = "#FF0D00"))
	configure(item_combat(armor_penetration = 50))

/obj/item/projectile/beam/xray
	name = "xray beam"
	icon_state = "xray"
	fire_sound = SFX_WEAPONS_ELUGER
	damage = 25
	hud_state = "laser_sniper"

	muzzle_type = /obj/effect/projectile/muzzle/xray
	tracer_type = /obj/effect/projectile/tracer/xray
	impact_type = /obj/effect/projectile/impact/xray

CAPABILITIES(/obj/item/projectile/beam/xray)
	configure(light_glow(color = "#00CC33"))
	configure(item_combat(armor_penetration = 50))

/obj/item/projectile/beam/gamma
	name = "gamma beam"
	icon_state = "xray"
	fire_sound = SFX_WEAPONS_ELUGER
	damage = 12
	irradiate = 20
	hud_state = "laser_sniper"

	muzzle_type = /obj/effect/projectile/muzzle/xray
	tracer_type = /obj/effect/projectile/tracer/xray
	impact_type = /obj/effect/projectile/impact/xray

CAPABILITIES(/obj/item/projectile/beam/gamma)
	configure(light_glow(color = "#00CC33"))
	configure(item_combat(armor_penetration = 90))

/obj/item/projectile/beam/cyan
	name = "cyan beam"
	icon_state = "cyan"
	fire_sound = SFX_WEAPONS_ELUGER
	damage = 40
	hud_state = "laser_disabler"

	muzzle_type = /obj/effect/projectile/muzzle/laser_omni
	tracer_type = /obj/effect/projectile/tracer/laser_omni
	impact_type = /obj/effect/projectile/impact/laser_omni

CAPABILITIES(/obj/item/projectile/beam/cyan)
	configure(light_glow(color = "#00C6FF"))

/obj/item/projectile/beam/pulse
	name = "pulse"
	icon_state = "u_laser"
	fire_sound=SFX_WEAPONS_GAUSS_SHOOT // Needs a more meaty sound than what pulse.ogg currently is; this will be a placeholder for now.
	damage = 100	//Badmin toy, don't care
	hud_state = "pulse"

	muzzle_type = /obj/effect/projectile/muzzle/laser_pulse
	tracer_type = /obj/effect/projectile/tracer/laser_pulse
	impact_type = /obj/effect/projectile/impact/laser_pulse

CAPABILITIES(/obj/item/projectile/beam/pulse)
	configure(light_glow(color = "#0066FF"))
	configure(item_combat(armor_penetration = 100))

/obj/item/projectile/beam/pulse/on_hit(atom/target, blocked = 0)
	if(isturf(target))
		target.ex_act(2)
	..()

/obj/item/projectile/beam/emitter
	name = "emitter beam"
	icon_state = "emitter"
	fire_sound = SFX_WEAPONS_EMITTER
	damage = 0 // The actual damage is computed in /code/modules/power/singularity/emitter.dm
	excavation_amount = 70 // 3 shots to mine a turf
	hud_state = "laser_overcharge"

	muzzle_type = /obj/effect/projectile/muzzle/emitter
	tracer_type = /obj/effect/projectile/tracer/emitter
	impact_type = /obj/effect/projectile/impact/emitter

CAPABILITIES(/obj/item/projectile/beam/emitter)
	configure(light_glow(color = "#00CC33"))

/obj/item/projectile/beam/lasertag
	name = "lasertag beam"
	damage = 0
	eyeblur = 0
	excavation_amount = 0
	hud_state = "monkey"
	///What suits this beam can hit.
	var/list/allowed_suits = list(/obj/item/clothing/suit/lasertag/omni, /obj/item/clothing/suit/lasertag/bluetag, /obj/item/clothing/suit/lasertag/redtag) // ALLOW(instance_list): d: replaced per instance at runtime (2 assignments)

	///How much damage we do to the tag vest.
	var/tag_damage = 1

	combustion = FALSE

/obj/item/projectile/beam/lasertag/on_hit(atom/target, blocked = 0)
	return handle_lasertag_attack(target, firer, tag_damage, TRUE, allowed_suits = allowed_suits) //We can't shoot this in the first place without having the proper vest / vest_override, so we feed it vest_override = TRUE

/obj/item/projectile/beam/lasertag/blue
	icon_state = "bluelaser"
	hud_state = "monkey"
	muzzle_type = /obj/effect/projectile/muzzle/laser_blue
	tracer_type = /obj/effect/projectile/tracer/laser_blue
	impact_type = /obj/effect/projectile/impact/laser_blue
	allowed_suits = list(/obj/item/clothing/suit/lasertag/redtag, /obj/item/clothing/suit/lasertag/omni)

CAPABILITIES(/obj/item/projectile/beam/lasertag/blue)
	configure(light_glow(color = "#0066FF"))


/obj/item/projectile/beam/lasertag/red
	icon_state = "laser"
	hud_state = "monkey"
	allowed_suits = list(/obj/item/clothing/suit/lasertag/bluetag, /obj/item/clothing/suit/lasertag/omni)

CAPABILITIES(/obj/item/projectile/beam/lasertag/red)
	configure(light_glow(color = "#FF0D00"))

/obj/item/projectile/beam/lasertag/omni//A laser tag bolt that stuns EVERYONE
	icon_state = "omnilaser"
	hud_state = "monkey"
	allowed_suits = list(/obj/item/clothing/suit/lasertag)

	muzzle_type = /obj/effect/projectile/muzzle/laser_omni
	tracer_type = /obj/effect/projectile/tracer/laser_omni
	impact_type = /obj/effect/projectile/impact/laser_omni

CAPABILITIES(/obj/item/projectile/beam/lasertag/omni)
	configure(light_glow(color = "#AA24AF"))

/obj/item/projectile/beam/sniper
	name = "sniper beam"
	icon_state = "xray"
	fire_sound = SFX_WEAPONS_GAUSS_SHOOT
	damage = 50
	hud_state = "laser_sniper"

	muzzle_type = /obj/effect/projectile/muzzle/xray
	tracer_type = /obj/effect/projectile/tracer/xray
	impact_type = /obj/effect/projectile/impact/xray

CAPABILITIES(/obj/item/projectile/beam/sniper)
	configure(light_glow(color = "#00CC33"))
	configure(item_combat(armor_penetration = 10))

/obj/item/projectile/beam/stun
	name = "stun beam"
	icon_state = "stun"
	fire_sound = SFX_WEAPONS_TASER
	nodamage = 1
	taser_effect = 1
	agony = 35
	injury_kind = INJURY_PAIN



	combustion = FALSE

	muzzle_type = /obj/effect/projectile/muzzle/stun
	tracer_type = /obj/effect/projectile/tracer/stun
	impact_type = /obj/effect/projectile/impact/stun

	hud_state = "taser" // TGMC Ammo HUD port

CAPABILITIES(/obj/item/projectile/beam/stun)
	configure(light_glow(color = "#FFFFFF"))
	configure(item_sounds(hit = SFX_WEAPONS_ZAPBANG))

/obj/item/projectile/beam/stun/weak
	name = "weak stun beam"
	icon_state = "stun"
	agony = 25

/obj/item/projectile/beam/stun/med
	name = "stun beam"
	icon_state = "stun"
	agony = 30

/obj/item/projectile/beam/stun/disabler
	muzzle_type = /obj/effect/projectile/muzzle/laser_omni
	tracer_type = /obj/effect/projectile/tracer/laser_omni
	impact_type = /obj/effect/projectile/impact/laser_omni

/obj/item/projectile/beam/stun/disabler/on_hit(atom/target, blocked = 0, def_zone)
	. = ..(target, blocked, def_zone)

	if(. && isrobot(target) && prob(agony))
		var/mob/living/silicon/robot/R = target
		var/drainamt = agony * (rand(5, 15) / 10)
		R.drain_power(0, 0, drainamt)
		if(isrobot(firer)) // Mischevious sappers, the swarm drones are.
			var/mob/living/silicon/robot/A = firer
			if(A.cell)
				A.cell.give(drainamt * 2)

/obj/item/projectile/beam/stun/kin21
	name = "kinh21 stun beam"
	icon_state = "omnilaser"
	muzzle_type = /obj/effect/projectile/muzzle/laser_omni
	tracer_type = /obj/effect/projectile/tracer/laser_omni
	impact_type = /obj/effect/projectile/impact/laser_omni
	hud_state = "laser_disabler"

CAPABILITIES(/obj/item/projectile/beam/stun/kin21)
	configure(light_glow(color = "#0000FF"))

/obj/item/projectile/beam/stun/blue
	icon_state = "bluelaser"
	muzzle_type = /obj/effect/projectile/muzzle/laser_blue
	tracer_type = /obj/effect/projectile/tracer/laser_blue
	impact_type = /obj/effect/projectile/impact/laser_blue
	hud_state = "laser_disabler"

CAPABILITIES(/obj/item/projectile/beam/stun/blue)
	configure(light_glow(color = "#0066FF"))

/obj/item/projectile/beam/disable
	name = "disabler beam"
	icon_state = "omnilaser"
	nodamage = 1
	taser_effect = 1
	agony = 100 //One shot stuns for the time being until adjustments are fully made.
	injury_kind = INJURY_PAIN
	hud_state = "laser_disabler"

	muzzle_type = /obj/effect/projectile/muzzle/laser_omni
	tracer_type = /obj/effect/projectile/tracer/laser_omni
	impact_type = /obj/effect/projectile/impact/laser_omni

CAPABILITIES(/obj/item/projectile/beam/disable)
	configure(light_glow(color = "#00CECE"))

/obj/item/projectile/beam/shock
	name = "shock beam"
	icon_state = "lightning"
	injury_kind = INJURY_ELECTRIC

	muzzle_type = /obj/effect/projectile/muzzle/lightning
	tracer_type = /obj/effect/projectile/tracer/lightning
	impact_type = /obj/effect/projectile/impact/lightning

	damage = 30
	agony = 15
	eyeblur = 2
	hud_state = "taser"

CAPABILITIES(/obj/item/projectile/beam/shock)
	configure(item_sounds(hit = SFX_WEAPONS_ZAPBANG))

/obj/item/projectile/beam/shock/weak
	damage = 5
	agony = 10


//
// Projectile Beam Definitions
//

/obj/item/projectile/beam/pointdefense
	name = "point defense salvo"
	icon_state = "laser"
	damage = 15
	injury_kind = INJURY_ELECTRIC //You should be safe inside a voidsuit

	excavation_amount = 200 // Good at shooting rocks

	muzzle_type = /obj/effect/projectile/muzzle/pointdefense
	tracer_type = /obj/effect/projectile/tracer/pointdefense
	impact_type = /obj/effect/projectile/impact/pointdefense

CAPABILITIES(/obj/item/projectile/beam/pointdefense)
	configure(light_glow(color = COLOR_GOLD))
	configure(item_combat(sharp = FALSE))

// a physical/projectile coil-gun type pointdefense
/obj/item/projectile/beam/coildefense
	name = "defense coil salvo"
	icon_state = "coil"
	damage = 15
	injury_kind = INJURY_ELECTRIC //You should be safe inside a voidsuit

	excavation_amount = 200 // Good at shooting rocks

	muzzle_type = /obj/effect/projectile/muzzle/coildefense
	tracer_type = /obj/effect/projectile/tracer/coildefense
	impact_type = /obj/effect/projectile/impact/coildefense

CAPABILITIES(/obj/item/projectile/beam/coildefense)
	configure(light_glow(color = "#FFFFFF"))
	configure(item_combat(sharp = FALSE))


/obj/item/projectile/beam/precursor // added Precursor beam
	name = "precursor beam"
	icon_state = "alien beam"
	fire_sound = SFX_WEAPONS_MEDIUMLASER

	muzzle_type = /obj/effect/projectile/muzzle/precursor
	tracer_type = /obj/effect/projectile/tracer/precursor
	impact_type = /obj/effect/projectile/impact/precursor
	hud_state = "plasma_rifle"
	damage = 48

CAPABILITIES(/obj/item/projectile/beam/precursor)
	configure(light_glow(color = "#FF0099"))
	configure(light_glow(color = "#FF0099"))
	configure(item_combat(armor_penetration = 10))
/obj/item/projectile/beam/eluger
	name = "laser beam"
	icon_state = "xray"
	muzzle_type = /obj/effect/projectile/muzzle/xray
	tracer_type = /obj/effect/projectile/tracer/xray
	impact_type = /obj/effect/projectile/impact/xray
	hud_state = "laser"

CAPABILITIES(/obj/item/projectile/beam/eluger)
	configure(light_glow(color = "#00FF00"))

/obj/item/projectile/beam/imperial
	name = "laser beam"
	fire_sound = SFX_WEAPONS_MANDALORIAN
	icon_state = "darkb"
	muzzle_type = /obj/effect/projectile/muzzle/darkmatter
	tracer_type = /obj/effect/projectile/tracer/darkmatter
	impact_type = /obj/effect/projectile/impact/darkmatter
	hud_state = "plasma_rifle_blast"

CAPABILITIES(/obj/item/projectile/beam/imperial)
	configure(light_glow(color = "#8837A3"))

/obj/item/projectile/beam/rainbow
	name = "rainbow"
	fire_sound = SFX_WEAPONS_SPARKLE
	icon_state = "rainbow"
	muzzle_type = /obj/effect/projectile/muzzle/rainbow
	tracer_type = /obj/effect/projectile/tracer/rainbow
	impact_type = /obj/effect/projectile/impact/rainbow
	hud_state = "laser"
	damage = 20

CAPABILITIES(/obj/item/projectile/beam/rainbow)
	configure(light_glow(color = "#ffffff"))

/obj/item/projectile/beam/rainbow/non_lethal
	damage = 0
	agony = 50
	injury_kind = INJURY_PAIN

/obj/item/projectile/beam/sparkledog
	name = "rainbow"
	fire_sound = SFX_WEAPONS_SPARKLE
	icon_state = "rainbow"
	muzzle_type = /obj/effect/projectile/muzzle/rainbow
	tracer_type = /obj/effect/projectile/tracer/rainbow
	impact_type = /obj/effect/projectile/impact/rainbow
	hud_state = "laser"
	damage = 0
	nodamage = TRUE

CAPABILITIES(/obj/item/projectile/beam/sparkledog)
	configure(light_glow(color = "#ffffff"))

/obj/item/projectile/beam/sparkledog/on_hit(atom/target, blocked = 0)
	if(ishuman(target))
		var/mob/living/carbon/human/M = target
		M.status_at_least(STAT_DRUGGED, 20)
		if(M.is_injured())
			to_chat(target, span_notice("As the beam strikes you, you feel a little healthier!"))
			M.mend(TREAT_TISSUE_REPAIR, 5)
			M.mend(TREAT_BURN_CARE, 5)
	return 1

//
// Projectile Beam Definitions
//
/obj/item/projectile/beam/pointdefense
	name = "point defense salvo"
	icon_state = "laser"
	damage = 15
	injury_kind = INJURY_ELECTRIC
	hud_state = "monkey"
	excavation_amount = 200 // Good at shooting rocks

	muzzle_type = /obj/effect/projectile/muzzle/pointdefense
	tracer_type = /obj/effect/projectile/tracer/pointdefense
	impact_type = /obj/effect/projectile/impact/pointdefense

/obj/item/projectile/beam/coildefense
	name = "defense coil salvo"
	icon_state = "coil"
	damage = 15
	injury_kind = INJURY_ELECTRIC

	excavation_amount = 200 // Good at shooting rocks

	muzzle_type = /obj/effect/projectile/muzzle/coildefense
	tracer_type = /obj/effect/projectile/tracer/coildefense
	impact_type = /obj/effect/projectile/impact/coildefense

//
// Energy Net
//
/obj/item/projectile/beam/energy_net
	name = "energy net projection"
	icon_state = "xray"
	nodamage = 1
	agony = 5
	injury_kind = INJURY_PAIN
	hud_state = "flame_green"
	hud_state_empty = "flame_empty"

	var/net_type = /obj/item/energy_net

	muzzle_type = /obj/effect/projectile/muzzle/xray
	tracer_type = /obj/effect/projectile/tracer/xray
	impact_type = /obj/effect/projectile/impact/xray

CAPABILITIES(/obj/item/projectile/beam/energy_net)
	configure(light_glow(color = "#00CC33"))

/obj/item/projectile/beam/energy_net/on_hit(atom/netted)
	do_net(netted)
	..()

/obj/item/projectile/beam/energy_net/proc/do_net(mob/M)
	var/obj/item/energy_net/net = new net_type(get_turf(M))
	net.throw_impact(M, throwing)

//
// Shrinking Energy Net
//
/obj/item/projectile/beam/energy_net/shrink
	name = "compactor energy net projection"
	icon_state = "omnilaser"
	hud_state = "flame_blue"
	hud_state_empty = "flame_empty"

	net_type = /obj/item/energy_net/shrink

	muzzle_type = /obj/effect/projectile/muzzle/laser_omni
	tracer_type = /obj/effect/projectile/tracer/laser_omni
	impact_type = /obj/effect/projectile/impact/laser_omni

CAPABILITIES(/obj/item/projectile/beam/energy_net/shrink)
	configure(light_glow(color = "#00CC33"))

//
// Healing Beam
//
/obj/item/projectile/beam/medigun
	name = "healing beam"
	icon_state = "healbeam"
	damage = 0 //stops it damaging walls
	nodamage = TRUE
	hud_state = "laser_disabler"
	combustion = FALSE

	muzzle_type = /obj/effect/projectile/muzzle/medigun
	tracer_type = /obj/effect/projectile/tracer/medigun
	impact_type = /obj/effect/projectile/impact/medigun

CAPABILITIES(/obj/item/projectile/beam/medigun)
	configure(item_combat(no_attack_log = TRUE))
	configure(light_glow(color = "#80F5FF"))

/obj/item/projectile/beam/medigun/on_hit(atom/target, blocked = 0)
	if(ishuman(target))
		var/mob/living/carbon/human/M = target
		if(M.is_injured())
			var/obj/effect/overlay/pulse = new /obj/effect/overlay(get_turf(M))
			pulse.set_icon('icons/effects/effects.dmi')
			pulse.set_icon_state(XENO_CHEM_HEAL)
			pulse.name = XENO_CHEM_HEAL
			pulse.set_anchored(TRUE)
			pulse.expire(2 SECONDS)
			to_chat(target, span_notice("As the beam strikes you, your injuries close up!"))
			M.mend(TREAT_TISSUE_REPAIR, 15)
			M.mend(TREAT_BURN_CARE, 15)
			M.mend(TREAT_ANTITOXIN, 5)
			M.mend(TREAT_OXYGENATION, 5)
	return 1

/obj/item/projectile/beam/laser_vision
	name = "laser"
	damage = 10


// === merged from beams_ch.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/item/projectile/beam/phaser //The "medium" phaser beam.
	damage = 20
	mob_bonus_damage = 20
	icon = 'icons/obj/projectiles_ch.dmi'
	icon_state = "phaser"
	muzzle_type = /obj/effect/projectile/muzzle/phaser
	tracer_type = /obj/effect/projectile/tracer/phaser
	impact_type = /obj/effect/projectile/impact/phaser
	hud_state = "laser_heat"


/obj/item/projectile/beam/phaser/light
	damage = 10
	mob_bonus_damage = 10
	icon_state = "phaser_light"
	muzzle_type = /obj/effect/projectile/muzzle/phaser/light
	tracer_type = /obj/effect/projectile/tracer/phaser/light
	impact_type = /obj/effect/projectile/impact/phaser/light


/obj/item/projectile/beam/phaser/heavy
	damage = 30
	mob_bonus_damage = 30
	icon_state = "phaser_heavy"
	muzzle_type = /obj/effect/projectile/muzzle/phaser/heavy
	tracer_type = /obj/effect/projectile/tracer/phaser/heavy
	impact_type = /obj/effect/projectile/impact/phaser/heavy


/obj/item/projectile/beam/phaser/heavy/cannon
	damage = 40
	mob_bonus_damage = 40


/obj/effect/projectile/tracer/phaser
	icon = 'icons/obj/projectiles_ch.dmi'
	icon_state = "phaser_tracer"

CAPABILITIES(/obj/effect/projectile/tracer/phaser)
	configure(light_glow(color = "#F18F12", range = 2, power = 0.5))

/obj/effect/projectile/tracer/phaser/heavy
	icon_state = "phaser_heavy_tracer"

CAPABILITIES(/obj/effect/projectile/tracer/phaser/heavy)
	configure(light_glow(range = 3, power = 1))

/obj/effect/projectile/tracer/phaser/light
	icon_state = "phaser_light_tracer"

CAPABILITIES(/obj/effect/projectile/tracer/phaser/light)
	configure(light_glow(range = 1.5, power = 0.3))

/obj/effect/projectile/muzzle/phaser
	icon = 'icons/obj/projectiles_ch.dmi'
	icon_state = "phaser_muzzle"

CAPABILITIES(/obj/effect/projectile/muzzle/phaser)
	configure(light_glow(color = "#F18F12", range = 2, power = 0.5))

/obj/effect/projectile/muzzle/phaser/heavy
	icon_state = "phaser_heavy_muzzle"

CAPABILITIES(/obj/effect/projectile/muzzle/phaser/heavy)
	configure(light_glow(range = 3, power = 1))

/obj/effect/projectile/muzzle/phaser/light
	icon_state = "phaser_light_muzzle"

CAPABILITIES(/obj/effect/projectile/muzzle/phaser/light)
	configure(light_glow(range = 1.5, power = 0.3))

/obj/effect/projectile/impact/phaser
	icon = 'icons/obj/projectiles_ch.dmi'
	icon_state = "phaser_impact"

CAPABILITIES(/obj/effect/projectile/impact/phaser)
	configure(light_glow(color = "#F18F12", range = 2, power = 0.5))

/obj/effect/projectile/impact/phaser/heavy
	icon_state = "phaser_heavy_impact"

CAPABILITIES(/obj/effect/projectile/impact/phaser/heavy)
	configure(light_glow(range = 3, power = 1))

/obj/effect/projectile/impact/phaser/light
	icon_state = "phaser_light_impact"

CAPABILITIES(/obj/effect/projectile/impact/phaser/light)
	configure(light_glow(range = 1.5, power = 0.3))

/obj/effect/projectile/muzzle/vepr
	icon_state = "vepr_muzzle"

CAPABILITIES(/obj/effect/projectile/muzzle/vepr)
	configure(light_glow(color = "#FF6A00", range = 3, power = 1))

CAPABILITIES(/obj/item/projectile/beam/lasertag)
	configure(item_combat(no_attack_log = 1))
