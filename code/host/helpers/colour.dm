/proc/get_random_colour(simple, lower=0, upper=255)
	var/colour
	if(simple)
		colour = pick(list("FF0000","FF7F00","FFFF00","00FF00","0000FF","4B0082","8F00FF"))
	else
		for(var/i=1;i<=3;i++)
			var/temp_col = "[num2hex(rand(lower,upper), 2)]"
			if(length(temp_col )<2)
				temp_col  = "0[temp_col]"
			colour += temp_col
	return "#[colour]"

/proc/color_square(red, green, blue, hex)
	var/color = hex ? hex : "#[num2hex(red, 2)][num2hex(green, 2)][num2hex(blue, 2)]"
	return "<span style='font-face: fixedsys; font-size: 14px; background-color: [color]; color: [color]'>___</span>"
