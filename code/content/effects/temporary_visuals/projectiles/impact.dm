/obj/effect/projectile/impact
	name = "beam impact"
	icon = 'icons/obj/projectiles_impact.dmi'

/obj/effect/projectile/impact/laser_pulse
	icon_state = "impact_u_laser"

CAPABILITIES(/obj/effect/projectile/impact/laser_pulse)
	configure(light_glow(range = 2, power = 0.5, color = "#0066FF"))

/obj/effect/projectile/impact/laser_heavy
	icon_state = "impact_beam_heavy"

CAPABILITIES(/obj/effect/projectile/impact/laser_heavy)
	configure(light_glow(range = 3, power = 1, color = "#FF0D00"))

/obj/effect/projectile/impact/laser_em
	icon_state = "impact_em_laser"

CAPABILITIES(/obj/effect/projectile/impact/laser_em)
	configure(light_glow(range = 3, power = 1, color = "#00C6FF"))

/obj/effect/projectile/impact/xray
	icon_state = "impact_xray"

CAPABILITIES(/obj/effect/projectile/impact/xray)
	configure(light_glow(range = 2, power = 0.5, color = "#00CC33"))

/obj/effect/projectile/impact/laser_omni
	icon_state = "impact_omni"

CAPABILITIES(/obj/effect/projectile/impact/laser_omni)
	configure(light_glow(range = 2, power = 0.5, color = "#00C6FF"))

/obj/effect/projectile/impact/laser
	icon_state = "impact_laser"

CAPABILITIES(/obj/effect/projectile/impact/laser)
	configure(light_glow(range = 2, power = 0.5, color = "#FF0D00"))

/obj/effect/projectile/impact/laser_blue
	icon_state = "impact_blue"

CAPABILITIES(/obj/effect/projectile/impact/laser_blue)
	configure(light_glow(range = 2, power = 0.5, color = "#0066FF"))

/obj/effect/projectile/impact/emitter
	icon_state = "impact_emitter"

CAPABILITIES(/obj/effect/projectile/impact/emitter)
	configure(light_glow(range = 2, power = 0.5, color = "#00CC33"))

/obj/effect/projectile/impact/stun
	icon_state = "impact_stun"

CAPABILITIES(/obj/effect/projectile/impact/stun)
	configure(light_glow(range = 2, power = 0.5, color = "#FFFFFF"))

/obj/effect/projectile/impact/lightning
	icon_state = "impact_lightning"

CAPABILITIES(/obj/effect/projectile/impact/lightning)
	configure(light_glow(range = 2, power = 0.5, color = "#00C6FF"))

/obj/effect/projectile/impact/darkmatterstun
	icon_state = "impact_darkt"

CAPABILITIES(/obj/effect/projectile/impact/darkmatterstun)
	configure(light_glow(range = 2, power = 0.5, color = "#8837A3"))

/obj/effect/projectile/impact/inversion
	icon_state = "impact_invert"

CAPABILITIES(/obj/effect/projectile/impact/inversion)
	configure(light_glow(range = 2, power = -2, color = "#FFFFFF"))

/obj/effect/projectile/impact/darkmatter
	icon_state = "impact_darkb"

CAPABILITIES(/obj/effect/projectile/impact/darkmatter)
	configure(light_glow(range = 2, power = 0.5, color = "#8837A3"))

/obj/effect/projectile/impact/precursor // add precursor impact
	icon = 'icons/obj/projectiles_ch.dmi' // Fix path + replace missing file
	icon_state = "impact_prec"

CAPABILITIES(/obj/effect/projectile/impact/precursor)
	configure(light_glow(range = 2, power = 0.7, color = "#FF0099"))

/obj/effect/projectile/impact/tungsten
	icon_state = "impact_mhd_laser"

CAPABILITIES(/obj/effect/projectile/impact/tungsten)
	configure(light_glow(range = 4, power = 3, color = "#3300ff"))

// medigun
/obj/effect/projectile/impact/medigun
	icon = 'icons/obj/projectiles_vr.dmi'
	icon_state = "impact_medbeam"

CAPABILITIES(/obj/effect/projectile/impact/medigun)
	configure(light_glow(range = 2, power = 0.5, color = "#80F5FF"))
// ends
/obj/effect/projectile/impact/pointdefense
	icon_state = "impact_pointdef"

/obj/effect/projectile/impact/rainbow
	icon_state = "impact_rainbow"

CAPABILITIES(/obj/effect/projectile/impact/rainbow)
	configure(light_glow(range = 3, power = 1, color = "#ffffff"))

/obj/effect/projectile/impact/coildefense
	icon_state = "impact_coildef"

CAPABILITIES(/obj/effect/projectile/impact/coildefense)
	configure(light_glow(range = 2, power = 3, color = "#FFFFFF"))
