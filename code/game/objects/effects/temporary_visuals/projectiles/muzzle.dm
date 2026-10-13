/obj/effect/projectile/muzzle
	name = "muzzle flash"
	icon = 'icons/obj/projectiles_muzzle.dmi'

/obj/effect/projectile/muzzle/emitter
	icon_state = "muzzle_emitter"

CAPABILITIES(/obj/effect/projectile/muzzle/emitter)
	configure(light_glow(range = 2, power = 0.5, color = "#00CC33"))

/obj/effect/projectile/muzzle/laser_pulse
	icon_state = "muzzle_u_laser"

CAPABILITIES(/obj/effect/projectile/muzzle/laser_pulse)
	configure(light_glow(range = 2, power = 0.5, color = "#0066FF"))

/obj/effect/projectile/muzzle/pulse
	icon_state = "muzzle_pulse"

CAPABILITIES(/obj/effect/projectile/muzzle/pulse)
	configure(light_glow(range = 2, power = 0.5, color = "#0066FF"))

/obj/effect/projectile/muzzle/stun
	icon_state = "muzzle_stun"

CAPABILITIES(/obj/effect/projectile/muzzle/stun)
	configure(light_glow(range = 2, power = 0.5, color = "#FFFFFF"))

/obj/effect/projectile/muzzle/bullet
	icon_state = "muzzle_bullet"

CAPABILITIES(/obj/effect/projectile/muzzle/bullet)
	configure(light_glow(range = 2, power = 0.5, color = "#FFFFFF"))

/obj/effect/projectile/muzzle/laser_heavy
	icon_state = "muzzle_beam_heavy"

CAPABILITIES(/obj/effect/projectile/muzzle/laser_heavy)
	configure(light_glow(range = 3, power = 1, color = "#FF0D00"))

/obj/effect/projectile/muzzle/laser_em
	icon_state = "muzzle_em_laser"

CAPABILITIES(/obj/effect/projectile/muzzle/laser_em)
	configure(light_glow(range = 3, power = 1, color = "#00C6FF"))

/obj/effect/projectile/muzzle/lightning
	icon_state = "muzzle_lightning"

CAPABILITIES(/obj/effect/projectile/muzzle/lightning)
	configure(light_glow(range = 2, power = 0.5, color = "#00C6FF"))

/obj/effect/projectile/muzzle/darkmatterstun
	icon_state = "muzzle_darkt"

CAPABILITIES(/obj/effect/projectile/muzzle/darkmatterstun)
	configure(light_glow(range = 2, power = 0.5, color = "#8837A3"))

/obj/effect/projectile/muzzle/laser_blue
	icon_state = "muzzle_blue"

CAPABILITIES(/obj/effect/projectile/muzzle/laser_blue)
	configure(light_glow(range = 2, power = 0.5, color = "#0066FF"))

/obj/effect/projectile/muzzle/darkmatter
	icon_state = "muzzle_darkb"

CAPABILITIES(/obj/effect/projectile/muzzle/darkmatter)
	configure(light_glow(range = 2, power = 0.5, color = "#8837A3"))

/obj/effect/projectile/muzzle/precursor // add Precursor muzzle
	icon = 'icons/obj/projectiles_ch.dmi' // Fix path + replace missing file
	icon_state = "muzzle_prec"

CAPABILITIES(/obj/effect/projectile/muzzle/precursor)
	configure(light_glow(range = 2, power = 0.7, color = "#FF0099"))

/obj/effect/projectile/muzzle/inversion
	icon_state = "muzzle_invert"

CAPABILITIES(/obj/effect/projectile/muzzle/inversion)
	configure(light_glow(range = 2, power = -2, color = "#FFFFFF"))

/obj/effect/projectile/muzzle/xray
	icon_state = "muzzle_xray"

CAPABILITIES(/obj/effect/projectile/muzzle/xray)
	configure(light_glow(range = 2, power = 0.5, color = "#00CC33"))

/obj/effect/projectile/muzzle/laser_omni
	icon_state = "muzzle_omni"

CAPABILITIES(/obj/effect/projectile/muzzle/laser_omni)
	configure(light_glow(range = 2, power = 0.5, color = "#00C6FF"))

/obj/effect/projectile/muzzle/laser
	icon_state = "muzzle_laser"

CAPABILITIES(/obj/effect/projectile/muzzle/laser)
	configure(light_glow(range = 2, power = 0.5, color = "#FF0D00"))

/obj/effect/projectile/muzzle/tungsten
	icon_state = "muzzle_mhd_laser"

CAPABILITIES(/obj/effect/projectile/muzzle/tungsten)
	configure(light_glow(range = 4, power = 3, color = "#3300ff"))

// medigun
/obj/effect/projectile/muzzle/medigun
	icon = 'icons/obj/projectiles_vr.dmi'
	icon_state = "muzzle_medbeam"

CAPABILITIES(/obj/effect/projectile/muzzle/medigun)
	configure(light_glow(range = 2, power = 0.5, color = "#80F5FF"))
// ends
/obj/effect/projectile/muzzle/pointdefense
	icon_state = "muzzle_pointdef"

/obj/effect/projectile/muzzle/rainbow
	icon_state = "muzzle_rainbow"

CAPABILITIES(/obj/effect/projectile/muzzle/rainbow)
	configure(light_glow(range = 3, power = 1, color = "#ffffff"))

/obj/effect/projectile/muzzle/coildefense
	icon_state = "muzzle_coildef"

CAPABILITIES(/obj/effect/projectile/muzzle/coildefense)
	configure(light_glow(range = 3, power = 1, color = "#FFFFFF"))
