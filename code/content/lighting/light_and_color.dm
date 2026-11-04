/atom/proc/get_light_and_color(atom/origin)
	if(origin)
		set_color(origin.color)
		set_glow(src, GLOW(glow_of(origin).range, glow_of(origin).power, glow_of(origin).color))
