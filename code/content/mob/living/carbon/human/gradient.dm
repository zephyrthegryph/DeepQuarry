GLOBAL_LIST_INIT(hair_gradients, list(
	"None" = "none",
	"Fade (Up)" = "fadeup",
	"Fade (Down)" = "fadedown",
	"Fade Low (Up)" = "fadeup_low",
	"Bottom Flat" = "bottomflat",
	"Fade Low (Down)" = "fadedown_low",
	"Vertical Split" = "vsplit",
	"Reflected" = "reflected",
	"Reflected (Inverted)" = "reflected_inverse",
	"Reflected High" = "reflected_high",
	"Reflected High (Inverted)" = "reflected_inverse_high",
	"Wavy" = "wavy",
	"Striped" = "striped",
	"Striped (Vertical)" = "striped_vertical"
	))

/// The icon state of a hair gradient, from either form a character carries: the id character setup saves ("fadeup")
/// or the display name the shapeshifter and DNA paths use ("Fade (Up)"). Null when it is neither.
/proc/hair_gradient_state(style)
	if(!istext(style))
		return null
	if(GLOB.hair_gradients[style])
		return GLOB.hair_gradients[style]
	for(var/name in GLOB.hair_gradients)
		if(GLOB.hair_gradients[name] == style)
			return style
	return null

/// The position of a hair gradient in GLOB.hair_gradients (DNA stores it), from either form; 0 when it is neither.
/proc/hair_gradient_index(style)
	var/state = hair_gradient_state(style)
	for(var/i in 1 to length(GLOB.hair_gradients))
		if(GLOB.hair_gradients[GLOB.hair_gradients[i]] == state)
			return i
	return 0
