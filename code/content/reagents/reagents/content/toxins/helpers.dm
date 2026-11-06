/mob/living/carbon/human/proc/slime_color_shift(color_shift)
	// each channel (red, green, blue) of skin, hair and beard shifts at a one-in-three chance; a zero channel stays
	for(var/channel in 1 to 3)
		if(!prob(33))
			continue
		var/list/channels = hex2rgb(looks.skin_color)
		var/value = channels[channel]
		if(value)
			looks.set_skin_color(colour_set_channel(looks.skin_color, channel, value + color_shift))
		channels = hex2rgb(looks.hair_color)
		value = channels[channel]
		if(value)
			looks.set_hair_color(colour_set_channel(looks.hair_color, channel, value + color_shift))
		channels = hex2rgb(looks.facial_color)
		value = channels[channel]
		if(value)
			looks.set_facial_color(colour_set_channel(looks.facial_color, channel, value + color_shift))
