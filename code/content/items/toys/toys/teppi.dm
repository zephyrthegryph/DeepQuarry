/obj/item/toy/plushie/teppi
	name = "teppi plushie"
	desc = "A soft, fluffy plushie made out of real teppi fur!"
	icon = 'icons/obj/toy_ch.dmi'
	icon_state = "teppi"
	pokephrase = "Gyooooooooh!"

/obj/item/toy/plushie/teppi/alt
	name = "teppi plush"
	desc = "No teppi were harmed in the creation of this plushie."
	icon_state = "teppialt"

/// Old attack_self: the teppi noise, then the plushie's squeeze.
/obj/item/toy/plushie/teppi/squeezed(mob/user, stance)
	if(stance == I_HURT || stance == I_GRAB)
		play_sfx(user, SFX_VOICE_TEPPI_ROAR)
	else
		var/teppi_noise = SFX_VOICE_TEPPI_WHINE_MIX
		playsound(user, teppi_noise, 10, 0)
		src.visible_message(span_notice("Gyooooooooh!"))
	return ..()
