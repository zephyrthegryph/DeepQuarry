/datum/trait/neutral/bloodsucker_freeform
	name = "Bloodsucker"
	desc = "You get fangs that can be used to drain blood from prey."
	tutorial = "This trait allows you to consume blood on top of normal food! <br> \
		You can do this by clicking bloodbags in your hand on harm intent, drinking from glasses, blood tomatoes \
		or finding a (un)willing donor for your appropriate appendage! <br><br> \
		Controls for taking blood from your victim can be changed at will by trying to drink from yourself. <br>\
		Intent-based control scheme: <br> \
		HELP - Loud, No Bleeding <br> \
		DISARM - Subtle, Causes bleeding <br> \
		GRAB - Subtle, No Bleeding <br> \
		HARM - Loud, Causes Bleeding"
	cost = 0
	custom_only = FALSE
	var_changes = list("bloodsucker" = TRUE)
	excludes = list(/datum/trait/neutral/bloodsucker, /datum/trait/positive/bloodsucker_plus)

/datum/trait/neutral/bloodsucker_freeform/apply(datum/species/S,mob/living/carbon/human/H)
	..()
	grant(H, granted_verb(/mob/living/carbon/human/proc/bloodsuck), src)
