/obj/item/grenade/anti_photon
	desc = "An experimental device for temporarily removing light in a limited area."
	name = "photon disruption grenade"
	icon = 'icons/obj/grenade.dmi'
	icon_state = "emp"
	det_time = 20
	var/light_sound = SFX_EFFECTS_PHASEIN
	var/blast_sound = SFX_EFFECTS_BANG

/obj/item/grenade/anti_photon/detonate(parent_callback = FALSE)
	if(parent_callback) // An awful way to do this, but the spawn() setup left me no choice when porting to timers
		..()
		return
	playsound(src, light_sound, 50, 1, 5)
	set_light(10, -10, "#FFFFFF")

	var/extra_delay = rand(0,90)
	after(src, 20 SECONDS + extra_delay, PROC_REF(grenade_light), with = list(extra_delay))

/obj/item/grenade/anti_photon/proc/grenade_light(extra_delay)
	PRIVATE_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	if(prob(10+extra_delay))
		set_light(10, 10, "#[num2hex(rand(64,255), 2)][num2hex(rand(64,255), 2)][num2hex(rand(64,255), 2)]")
	after(src, 1 SECONDS, PROC_REF(grenade_blast))

/obj/item/grenade/anti_photon/proc/grenade_blast()
	PRIVATE_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)
	detonate(TRUE) // See above for this sinful choice
	playsound(src, blast_sound, 50, 1, 5)
	spent(src)
