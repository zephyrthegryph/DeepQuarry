/obj/item/toy/plushie/dragon
	name = "dragon plushie"
	desc = "A soft plushie in the shape of a dragon. How ferocious!"
	icon = 'icons/obj/toy.dmi'
	icon_state = "reddragon"
	COOLDOWN_DECLARE(cooldown)
	special_handling = TRUE

CAPABILITIES(/obj/item/toy/plushie/dragon)
	without("hug")
	without("poke")
	without("strangle")
	without("punch")
	op("dragon_squeeze", in_hand(), label("Squeeze"), then(PROC_REF(interaction_dragon_squeeze)))
	rolls(nameof(pokephrase), pick_one(list("ROAR!", "RAWR!", "GAWR!", "GRR!", "GROAR!", "GRAH!", "Weh!", "Merp!")))

/// Old attack_self: the dragon noise. The plushie's squeeze does nothing for it (special_handling).
/obj/item/toy/plushie/dragon/proc/interaction_dragon_squeeze(datum/act/op/A)
	var/mob/user = A.actor
	if(COOLDOWN_FINISHED(src, cooldown))
		switch(pokephrase)
			if("Weh!")
				play_sfx(user, SFX_VOICE_WEH)
			if("Merp!")
				play_sfx(user, SFX_VOICE_MERP)
			else
				play_sfx(user, SFX_VOICE_ROARBARK)
		COOLDOWN_START(src, cooldown, 5 SECONDS)
	return TRUE

/obj/item/toy/plushie/dragon/green
	name = "green dragon plushie"
	icon_state = "greendragon"

/obj/item/toy/plushie/dragon/purple
	name = "purple dragon plushie"
	icon_state = "purpledragon"

/obj/item/toy/plushie/dragon/white_east
	name = "white eastern dragon plushie"
	icon_state = "whiteeasterndragon"

/obj/item/toy/plushie/dragon/red_east
	name = "red eastern dragon plushie"
	icon_state = "redeasterndragon"

/obj/item/toy/plushie/dragon/green_east
	name = "green eastern dragon plushie"
	icon_state = "greeneasterndragon"

/obj/item/toy/plushie/dragon/gold_east
	name = "golden eastern dragon plushie"
	desc = "A soft plushie of a shiny golden dragon. Made of Real* gold!"
	icon_state = "goldeasterndragon"
	pokephrase = "Rawr~!"
