/datum/technomancer/spell/audible_deception
	name = "Audible Deception"
	desc = "Allows you to create a specific sound at a location of your choosing."
	enhancement_desc = "An extremely loud bike horn sound that costs  large amount of energy and instability becomes available, \
	which will deafen and stun all who are near the targeted tile, including yourself if unprotected."
	cost = 50
	obj_path = /obj/item/spell/audible_deception
	ability_icon_state = "tech_audibledeception"
	category = UTILITY_SPELLS

/obj/item/spell/audible_deception
	name = "audible deception"
	icon_state = "audible_deception"
	desc = "Make them all paranoid!"
	cast_methods = CAST_RANGED | CAST_USE
	aspect = ASPECT_AIR
	cooldown = 10
	var/static/list/available_sounds = list(
		"Blade Slice"			=	SFX_WEAPONS_BLADESLICE,
		"Energy Blade Slice"	=	SFX_WEAPONS_BLADE1,
		"Explosions"			=	SFX_EXPLOSION,
		"Distant Explosion"		=	SFX_EFFECTS_EXPLOSIONFAR,
		"Sparks"				=	SFX_SPARKS,
		"Punches"				=	SFX_PUNCH,
		"Glass Shattering"		=	SFX_SHATTER,
		"Grille Damage"			=	SFX_EFFECTS_GRILLEHIT,
		"Energy Pulse"			=	SFX_EFFECTS_EMPULSE,
		"Airlock"				=	SFX_MACHINES_DOOR_OLD_AIRLOCK,
		"Airlock Creak"			=	SFX_MACHINES_DOOR_AIRLOCK_CREAKING,

		"Shotgun Pumping"		=	SFX_WEAPONS_SHOTGUNPUMP,
		"Flash"					=	SFX_WEAPONS_FLASH,
		"Bite"					=	SFX_WEAPONS_BITE,
		"Gun Firing"			=	SFX_WEAPONS_GUNSHOT1,
		"Desert Eagle Firing"	=	SFX_WEAPONS_GUNSHOT_DEAGLE,
		"Rifle Firing"			=	SFX_WEAPONS_GUNSHOT_GENERIC_RIFLE,
		"Sniper Rifle Firing"	=	SFX_WEAPONS_GUNSHOT_SNIPER,
		"AT Rifle Firing"		=	SFX_WEAPONS_GUNSHOT_CANNON,
		"Shotgun Firing"		=	SFX_WEAPONS_GUNSHOT_SHOTGUN,
		"Handgun Firing"		=	SFX_WEAPONS_GUNSHOT2,
		"Machinegun Firing"		=	SFX_WEAPONS_GUNSHOT_MACHINEGUN,
		"Rocket Launcher Firing"=	SFX_WEAPONS_RPG,
		"Taser Firing"			=	SFX_WEAPONS_TASER,
		"Laser Gun Firing"		=	SFX_WEAPONS_LASER,
		"E-Luger Firing"		=	SFX_WEAPONS_ELUGER,
		"Xray Gun Firing"		=	SFX_WEAPONS_LASER3,
		"Pulse Gun Firing"		=	SFX_WEAPONS_PULSE,
		"Energy Sniper Firing"	=	SFX_WEAPONS_GAUSS_SHOOT,
		"Emitter Firing"		=	SFX_WEAPONS_EMITTER,
		"Energy Blade On"		=	SFX_WEAPONS_SABERON,
		"Energy Blade Off"		=	SFX_WEAPONS_SABEROFF,
		"Wire Restraints"		=	SFX_WEAPONS_CABLECUFF,
		"Handcuffs"				=	SFX_WEAPONS_HANDCUFFS,

		"Crowbar"				=	SFX_ITEMS_CROWBAR,
		"Screwdriver"			=	SFX_ITEMS_SCREWDRIVER,
		"Welding"				=	SFX_ITEMS_WELDER,
		"Wirecutting"			=	SFX_ITEMS_WIRECUTTER,

		"Nymph Chirping"		=	SFX_MISC_NYMPHCHIRP,
		"Sad Trombone"			=	SFX_MISC_SADTROMBONE,
		"Honk"					=	SFX_ITEMS_BIKEHORN,
		"Bone Fracture"			=	SFX_FRACTURE,
		)
	var/selected_sound = null

/obj/item/spell/audible_deception/on_use_cast(mob/user)
	var/list/sound_options = available_sounds.Copy()
	if(check_for_scepter())
		sound_options["!!AIR HORN!!"] = 'sound/items/AirHorn.ogg'
	open_request(src, /datum/prompt/choice/technomancer_carried, PROC_REF(deception_sound_chosen), answerer = user, subject = src, title = "Sounds", question = "Select the sound you want to make.", choices = sound_options)

/obj/item/spell/audible_deception/proc/deception_sound_chosen(datum/act/request/A)
	if(!A.answer)
		return
	return deception_sound_chosen_apply(A)

/obj/item/spell/audible_deception/proc/deception_sound_chosen_apply(datum/act/request/A)
	var/datum/prompt/choice/technomancer_carried/ask = A.answer
	if(ask.value)
		selected_sound = ask.choices[ask.value]

/obj/item/spell/audible_deception/on_ranged_cast(atom/hit_atom, mob/living/user)
	var/turf/T = get_turf(hit_atom)
	if(selected_sound && pay_energy(200))
		playsound(src, selected_sound, 80, 1, -1)
		adjust_instability(1)
		// Air Horn time.
		if(selected_sound == SFX_ITEMS_AIRHORN && pay_energy(3800))
			adjust_instability(49) // Pay for your sins.
			for(var/mob/living/carbon/M in ohearers(6, T))
				if(M.get_ear_protection() >= 2)
					continue
				M.status_set(STAT_SLEEPING, 0)
				M.status_adjust(STAT_STUTTERING, 20)
				M.status_adjust(STAT_DEAFENED, 30)
				M.deaf_loop.start() // Ear Ringing/Deafness
				M.status_at_least(STAT_WEAKENED, 3)
				if(prob(30))
					M.status_at_least(STAT_STUNNED, 10)
					M.status_at_least(STAT_PARALYZED, 4)
					M.status_at_least(STAT_SLEEPING, 4)
				else
					M.status_adjust(STAT_JITTERY, 50)
				to_chat(M, span_red(span_massive(span_bold("HONK"))))
