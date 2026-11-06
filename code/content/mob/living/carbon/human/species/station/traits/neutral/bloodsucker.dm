/datum/trait/neutral/bloodsucker
	name = "Bloodsucker, Obligate"
	desc = "Makes you unable to gain nutrition from anything but blood. To compenstate, you get fangs that can be used to drain blood from prey."
	tutorial = "This trait forces you to only consume blood - you cannot have normal food anymore. Vore is, of course, an exception! <br> \
		You can satisfy this by clicking bloodbags in your hand on harm intent, drinking from glasses, blood tomatoes \
		or finding a (un)willing donor for your appropriate appendage! <br><br> \
		Controls for taking blood from your victim can be changed at will by trying to drink from yourself. <br>\
		Intent-based control scheme: <br> \
		HELP - Loud, No Bleeding <br> \
		DISARM - Subtle, Causes bleeding <br> \
		GRAB - Subtle, No Bleeding <br> \
		HARM - Loud, Causes Bleeding"

	cost = 0
	custom_only = FALSE
	var_changes = list("organic_food_coeff" = 0, "bloodsucker" = TRUE, "hunger_alert_style" = HUNGER_ALERT_VAMPIRE) //The verb is given in human.dm
	excludes = list(/datum/trait/neutral/bloodsucker_freeform, /datum/trait/positive/bloodsucker_plus)

/datum/trait/neutral/bloodsucker/apply(datum/species/S,mob/living/carbon/human/H)
	..()
	grant(H, granted_verb(/mob/living/carbon/human/proc/bloodsuck), src)
