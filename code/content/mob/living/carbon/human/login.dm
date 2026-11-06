/mob/living/carbon/human/Login()
	..()
	update_hud()
	if(client.prefs) // Safety, just in case so we don't runtime.
		consider_birthday()
	if(species) species.handle_login_special(src)
	return
