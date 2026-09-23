/datum/modifier/trait
	flags = MODIFIER_GENETIC	// We want traits to persist if the person gets cloned.


/datum/modifier/trait/flimsy
	name = "flimsy"
	desc = "You're more fragile than most, and have less of an ability to endure harm."

	on_created_text = span_warning("You feel rather weak.")
	on_expired_text = span_notice("You feel your strength returning to you.")

	factors = alist(BF_ENDURANCE_MULT = 0.8)

/datum/modifier/trait/frail
	name = "frail"
	desc = "Your body is very fragile, and has even less of an ability to endure harm."

	on_created_text = span_warning("You feel really weak.")
	on_expired_text = span_notice("You feel your strength returning to you.")

	factors = alist(BF_ENDURANCE_MULT = 0.6)

/datum/modifier/trait/weak
	name = "weak"
	desc = "A lack of physical strength causes a diminshed capability in close quarters combat"

	factors = alist(BF_MELEE_DAMAGE = 0.8)

/datum/modifier/trait/wimpy
	name = "wimpy"
	desc = "An extreme lack of physical strength causes greatly diminished capability in close quarters combat."

	factors = alist(BF_MELEE_DAMAGE = 0.6)

/datum/modifier/trait/haemophilia
	name = "haemophilia"
	desc = "You bleed much faster than average."

	factors = alist(BF_BLEEDING = 3.0)

/datum/modifier/trait/inaccurate
	name = "Inaccurate"
	desc = "You're rather inexperienced with guns, you've never used one in your life, or you're just really rusty.  \
	Regardless, you find it quite difficult to land shots where you wanted them to go."

	factors = alist(BF_ACCURACY = -15, BF_DISPERSION = 1)

/datum/modifier/trait/high_metabolism
	name = "High Metabolsim"
	desc = "Your body's metabolism is faster than average."

	factors = alist(BF_METABOLISM = 2.0, BF_HEALING_RECEIVED = 1.4)

/datum/modifier/trait/low_metabolism
	name = "Low Metabolism"
	desc = "Your body's metabolism is slower than average."

	factors = alist(BF_METABOLISM = 0.5, BF_HEALING_RECEIVED = 0.6)

/datum/modifier/trait/taller
	name = "Taller"
	desc = "Your body is taller than average."
	factors = alist(BF_ICON_SCALE_X = 1, BF_ICON_SCALE_Y = 1.09)

/datum/modifier/trait/tall
	name = "Tall"
	desc = "Your body is a bit taller than average."
	factors = alist(BF_ICON_SCALE_X = 1, BF_ICON_SCALE_Y = 1.05)

/datum/modifier/trait/short
	name = "Short"
	desc = "Your body is a bit shorter than average."
	factors = alist(BF_ICON_SCALE_X = 1, BF_ICON_SCALE_Y = 0.95)


/datum/modifier/trait/shorter
	name = "Shorter"
	desc = "You are shorter than average."
	factors = alist(BF_ICON_SCALE_X = 1, BF_ICON_SCALE_Y = 0.915)

/datum/modifier/trait/fat
	name = "Overweight"
	desc = "You are heavier than average."

	factors = alist(BF_METABOLISM = 1.2, BF_SLOWDOWN = 1.1, BF_ENDURANCE_MULT = 1.05, BF_ICON_SCALE_X = 1.054, BF_ICON_SCALE_Y = 1)

/datum/modifier/trait/obese
	name = "Obese"
	desc = "You are much heavier than average."
	factors = alist(BF_METABOLISM = 1.4, BF_SLOWDOWN = 1.2, BF_ENDURANCE_MULT = 1.10, BF_ICON_SCALE_X = 1.095, BF_ICON_SCALE_Y = 1)

/datum/modifier/trait/thin
	name = "Thin"
	desc = "You are skinnier than average."
	factors = alist(BF_METABOLISM = 0.8, BF_MELEE_DAMAGE = 0.95, BF_ENDURANCE_MULT = 0.95, BF_ICON_SCALE_X = 0.945, BF_ICON_SCALE_Y = 1)

/datum/modifier/trait/thinner
	name = "Very Thin"
	desc = "You are much skinnier than average."
	factors = alist(BF_METABOLISM = 0.6, BF_MELEE_DAMAGE = 0.9, BF_ENDURANCE_MULT = 0.90, BF_ICON_SCALE_X = 0.905, BF_ICON_SCALE_Y = 1)

/datum/modifier/trait/colorblind_protanopia
	name = "Protanopia"
	desc = "You have a form of red-green colorblindness. You cannot see reds, and have trouble distinguishing them from yellows and greens."

	client_color = MATRIX_Protanopia
	wire_colors_replace = PROTANOPIA_COLOR_REPLACE

/datum/modifier/trait/colorblind_deuteranopia
	name = "Deuteranopia"
	desc = "You have a form of red-green colorblindness. You cannot see greens, and have trouble distinguishing them from yellows and reds."

	client_color = MATRIX_Deuteranopia
	wire_colors_replace = DEUTERANOPIA_COLOR_REPLACE

/datum/modifier/trait/colorblind_tritanopia
	name = "Tritanopia"
	desc = "You have a form of blue-yellow colorblindness. You have trouble distinguishing between blues, greens, and yellows, and see blues and violets as dim."

	client_color = MATRIX_Tritanopia
	wire_colors_replace = TRITANOPIA_COLOR_REPLACE

/datum/modifier/trait/colorblind_taj
	name = "Colorblind - Blue-red"
	desc = "You are colorblind. You have a minor issue with blue colors and have difficulty recognizing them from red colors."

	client_color = MATRIX_Taj_Colorblind
	wire_colors_replace = TRITANOPIA_COLOR_REPLACE

/datum/modifier/trait/colorblind_vulp
	name = "Colorblind - Red-green"
	desc = "You are colorblind. You have a severe issue with green colors and have difficulty recognizing them from red colors."

	client_color = MATRIX_Vulp_Colorblind
	wire_colors_replace = PROTANOPIA_COLOR_REPLACE

/datum/modifier/trait/colorblind_monochrome
	name = "Monochromacy"
	desc = "You are fully colorblind. Your condition is rare, but you can see no colors at all."

	client_color = MATRIX_Monochromia
	wire_colors_replace = GREYSCALE_COLOR_REPLACE
