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

DECLARE_INTERACTIONS(/obj/item/firework_star/aesthetic/configurable, INTERACT_USE(null, PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/firework_star/aesthetic/configurable/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	return firework_setting_stage(user, held, interaction, list())

/obj/item/firework_star/aesthetic/configurable/proc/firework_setting_stage(mob/user, obj/item/held, datum/interaction/interaction, list/firework_answers)
	if(!("k119" in firework_answers))
		open_request(src, /datum/prompt/choice/firework_setting_review, PROC_REF(firework_setting_answered), answerer = user, firework_operator = user, firework_held = held, firework_interaction = interaction, firework_answers = firework_answers, firework_key = "k119", question = "What setting do you want to adjust?", title = "Firework Star", choices = list("Color", "Shape", "Nothing"), buttons = TRUE)
		return TRUE
	var/choice = firework_answers["k119"]
	if(isnull(choice))
		return TRUE
	if(src.loc != user)
		return TRUE

	if(choice == "Color")
		if(!("k124" in firework_answers))
			open_request(src, /datum/prompt/choice/firework_setting_review, PROC_REF(firework_setting_answered), answerer = user, firework_operator = user, firework_held = held, firework_interaction = interaction, firework_answers = firework_answers, firework_key = "k124", question = "What color would you like firework to be?", title = "Firework Star", choices = firework_colors)
			return TRUE
		var/color_choice = firework_answers["k124"]
		if(isnull(color_choice))
			return TRUE
		if(src.loc != user)
			return TRUE
		if(color_choice)
			current_color = color_choice

	if(choice == "Shape")
		if(!("k131" in firework_answers))
			open_request(src, /datum/prompt/choice/firework_setting_review, PROC_REF(firework_setting_answered), answerer = user, firework_operator = user, firework_held = held, firework_interaction = interaction, firework_answers = firework_answers, firework_key = "k131", question = "What shape would you like firework to be?", title = "Firework Star", choices = firework_shapes)
			return TRUE
		var/shape_choice = firework_answers["k131"]
		if(isnull(shape_choice))
			return TRUE
		if(src.loc != user)
			return TRUE
		if(shape_choice)
			current_shape = shape_choice
	return TRUE

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

/obj/item/firework_star/aesthetic/configurable/proc/firework_setting_answered(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/result/caught = safe_call(PROC_REF(firework_setting_apply), context)
	if(!caught.ok)
		stack_trace("Firework settings replay: [caught.error]")
	SStgui.update_uis(src)
	return caught.value

/obj/item/firework_star/aesthetic/configurable/proc/firework_setting_apply(datum/act/request/context)
	var/datum/prompt/choice/firework_setting_review/ask = context.answer
	var/list/firework_answers = ask.firework_answers.Copy()
	firework_answers[ask.firework_key] = ask.answer_value
	return firework_setting_stage(ask.firework_operator, ask.firework_held, ask.firework_interaction, firework_answers)

/datum/prompt/choice/firework_setting_review
	timeout = 0
	var/list/firework_answers
	var/firework_key
	var/mob/firework_operator
	var/firework_operator_expected = FALSE
	var/obj/item/firework_held
	var/firework_held_expected = FALSE
	var/datum/interaction/firework_interaction
	var/firework_interaction_expected = FALSE

CAPABILITIES(/datum/prompt/choice/firework_setting_review)
	ref_one(nameof(firework_operator), /mob)
	ref_one(nameof(firework_held), /obj/item)
	ref_one(nameof(firework_interaction), /datum/interaction)

/datum/prompt/choice/firework_setting_review/prepare(datum/act/context)
	. = ..()
	var/mob/captured_operator = firework_operator
	firework_operator_expected = !isnull(captured_operator)
	rel_clear(src, nameof(firework_operator))
	if(captured_operator && !QDELETED(captured_operator))
		rel_set(src, nameof(firework_operator), captured_operator)
	var/obj/item/captured_held = firework_held
	firework_held_expected = !isnull(captured_held)
	rel_clear(src, nameof(firework_held))
	if(captured_held && !QDELETED(captured_held))
		rel_set(src, nameof(firework_held), captured_held)
	var/datum/interaction/captured_interaction = firework_interaction
	firework_interaction_expected = !isnull(captured_interaction)
	rel_clear(src, nameof(firework_interaction))
	if(captured_interaction && !QDELETED(captured_interaction))
		rel_set(src, nameof(firework_interaction), captured_interaction)

/datum/prompt/choice/firework_setting_review/recheck_extra()
	if((firework_operator_expected && QDELETED(firework_operator)) || (firework_held_expected && QDELETED(firework_held)) || (firework_interaction_expected && QDELETED(firework_interaction)))
		return "gone"
