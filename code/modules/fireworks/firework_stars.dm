#define T_FIREWORK_WEATHER_STAR(name)	"weather firework star (" + (name) + ")"

/obj/item/firework_star
	icon = 'icons/obj/firework_stars.dmi'
	name = "firework star"
	desc = "A very tightly compacted ball of chemicals for use with firework launcher."
	icon_state = "star"
	w_class = ITEMSIZE_SMALL

/obj/item/firework_star/proc/trigger_firework(datum/weather_holder/w_holder)
	return


/obj/item/firework_star/weather
	name = "weather firework star"
	desc = "A firework star designed to alter a weather, rather than put on a show."
	var/weather_type

/obj/item/firework_star/weather/trigger_firework(datum/weather_holder/w_holder)
	if(!w_holder)						// Sanity
		return
	if(w_holder.firework_override)		// Make sure weather-based events can't be interfered with
		return
	if(weather_type && (weather_type in w_holder.allowed_weather_types))
		w_holder.message_all_outdoor_players("Something seems to flash in the sky, as weather starts to rapidly shift!")
		w_holder.queue_imminent_weather(weather_type)
		var/datum/weather/our_weather = LAZYACCESS(w_holder.allowed_weather_types, weather_type)
		w_holder.message_all_outdoor_players(our_weather.imminent_transition_message)

/obj/item/firework_star/weather/clear
	name = T_FIREWORK_WEATHER_STAR("CLEAR SKY")
	weather_type = WEATHER_CLEAR
	icon_state = "clear"

/obj/item/firework_star/weather/overcast
	name = T_FIREWORK_WEATHER_STAR("CLOUDY")
	weather_type = WEATHER_OVERCAST
	icon_state = "cloudy"

/obj/item/firework_star/weather/fog
	name = T_FIREWORK_WEATHER_STAR("FOG")
	weather_type = WEATHER_FOG
	icon_state = "cloudy"

/obj/item/firework_star/weather/rain
	name = T_FIREWORK_WEATHER_STAR("RAIN")
	weather_type = WEATHER_RAIN
	icon_state = "rain"

/obj/item/firework_star/weather/storm
	name = T_FIREWORK_WEATHER_STAR("STORM")
	weather_type = WEATHER_STORM
	icon_state = "rain"

/obj/item/firework_star/weather/light_snow
	name = T_FIREWORK_WEATHER_STAR("SNOW - LIGHT")
	weather_type = WEATHER_LIGHT_SNOW
	icon_state = "snow"

/obj/item/firework_star/weather/snow
	name = T_FIREWORK_WEATHER_STAR("SNOW - MEDIUM")
	weather_type = WEATHER_SNOW
	icon_state = "snow"

/obj/item/firework_star/weather/blizzard
	name = T_FIREWORK_WEATHER_STAR("SNOW - HEAVY")
	weather_type = WEATHER_BLIZZARD
	icon_state = "snow"

/obj/item/firework_star/weather/hail
	name = T_FIREWORK_WEATHER_STAR("HAIL")
	weather_type = WEATHER_HAIL
	icon_state = "snow"

/obj/item/firework_star/weather/fallout
	name = T_FIREWORK_WEATHER_STAR("NUCLEAR")
	desc = "This is the worst idea ever."
	weather_type = WEATHER_FALLOUT_TEMP
	icon_state = "nuclear"

/obj/item/firework_star/weather/confetti
	name = T_FIREWORK_WEATHER_STAR("CONFETTI")
	desc = "A firework star designed to alter a weather, rather than put on a show. This one makes colorful confetti rain from the sky."
	weather_type = WEATHER_CONFETTI
	icon_state = "confetti"


/obj/item/firework_star/aesthetic
	name = "aesthetic firework star"
	desc = "A firework star designed to paint the sky with pretty lights."
	var/static/list/firework_adjectives = list("beautiful", "pretty", "fancy", "colorful", "bright", "shimmering")
	var/static/list/firework_colors = list("red", "orange", "yellow", "green", "cyan", "blue", "purple", "pink", "beige", "white")

/obj/item/firework_star/aesthetic/trigger_firework(datum/weather_holder/w_holder)
	if(!w_holder)
		return
	w_holder.message_all_outdoor_players(get_firework_message())

/obj/item/firework_star/aesthetic/proc/get_firework_message()
	return "You see a [pick(firework_adjectives)] explosion of [pick(firework_colors)] sparks in the sky!"

/obj/item/firework_star/aesthetic/configurable
	name = "configurable aesthetic firework star"
	desc = "A firework star designed to paint the sky with pretty lights. This one's advanced and can be configured to specific shapes or colors."
	icon_state = "config"
	var/current_color = "white"
	var/current_shape = "Random"
	var/static/list/firework_shapes = list("none", "Random",
								"a circle", "an oval", "a triangle", "a square", "a pentagon", "a hexagon", "an octagon", "a plus sign", "an x", "a star", "a spiral", "a heart", "a teardrop",
								"a smiling face", "a winking face", "a mouse", "a cat", "a dog", "a fox", "a bird", "a fish", "a lizard", "a bug", "a butterfly", "a robot", "a dragon", "a teppi", "a catslug",
								"a tree", "a leaf", "a flower", "a lightning bolt", "a cloud", "a sun", "a gemstone", "a flame", "a wrench", "a beaker", "a syringe", "a pickaxe", "a pair of handcuffs", "a crown",
								"a bottle", "a boat", "a spaceship",
								"Nanotrasen logo", "a geometric-looking letter S", "a dodecahedron")

CAPABILITIES(/obj/item/firework_star/aesthetic/configurable)
	op("self", in_hand(), priority(OP_PRIORITY_DEFAULT - 1),
		asks(/datum/prompt/choice, fields = list("question" = "What setting do you want to adjust?", "title" = "Firework Star", "choices" = list("Color", "Shape", "Nothing"), "buttons" = TRUE, "timeout" = 0), step = "setting"),
		asks(/datum/prompt/choice, fields = list("question" = "What color would you like firework to be?", "title" = "Firework Star", "choices" = computed(PROC_REF(firework_color_choices)), "timeout" = 0), step = "color", when = PROC_REF(asks_color)),
		asks(/datum/prompt/choice, fields = list("question" = "What shape would you like firework to be?", "title" = "Firework Star", "choices" = computed(PROC_REF(firework_shape_choices)), "timeout" = 0), step = "shape", when = PROC_REF(asks_shape)),
		then(PROC_REF(firework_settings_chosen)))

/obj/item/firework_star/aesthetic/configurable/proc/asks_color(datum/act/op/A)
	return A.step_value("setting") == "Color"

/obj/item/firework_star/aesthetic/configurable/proc/asks_shape(datum/act/op/A)
	return A.step_value("setting") == "Shape"

/obj/item/firework_star/aesthetic/configurable/proc/firework_color_choices(datum/act/op/A)
	return firework_colors

/obj/item/firework_star/aesthetic/configurable/proc/firework_shape_choices(datum/act/op/A)
	return firework_shapes

/// Old attack_self: adjust the chosen setting, if the star is still in hand.
/obj/item/firework_star/aesthetic/configurable/proc/firework_settings_chosen(datum/act/op/A)
	var/mob/user = A.actor
	if(src.loc != user)
		return OP_OK
	var/choice = A.step_value("setting")
	if(choice == "Color")
		var/color_choice = A.step_value("color")
		if(color_choice)
			current_color = color_choice
	else if(choice == "Shape")
		var/shape_choice = A.step_value("shape")
		if(shape_choice)
			current_shape = shape_choice
	return OP_OK

/obj/item/firework_star/aesthetic/configurable/get_firework_message()
	var/temp_shape = current_shape
	if(temp_shape == "Random")
		var/list/shapes_copy = firework_shapes.Copy()
		shapes_copy -= "Random"
		temp_shape = pick(shapes_copy)

	if(temp_shape == "none" || !temp_shape)
		return "You see a [pick(firework_adjectives)] explosion of [current_color] sparks in the sky!"
	else
		return "You see a [pick(firework_adjectives)] explosion of [current_color] sparks in the sky, forming into shape of [current_shape]!"

#undef T_FIREWORK_WEATHER_STAR
