/obj/machinery/holoposter
	name = "Holographic Poster"
	desc = "A wall-mounted holographic projector displaying advertisements by all manner of factions. How much do they pay to advertise here?"
	icon = 'icons/obj/holoposter_vr.dmi'
	icon_state = "off"
	anchored = TRUE
	use_power = 1
	idle_power_usage = 80
	power_channel = ENVIRON
	vis_flags = VIS_HIDE // They have an emissive that looks bad in openspace due to their wall-mounted nature
	var/icon_forced = FALSE
	var/examine_addon = "It appears to be powered off."
	var/alerting = FALSE

	var/static/list/postertypes = list(
		"hephaestus" = list(LIGHT_COLOR_CYAN, "Hephaestus Aeronautics, a subsidiary of Hephaestus Industries. Known to make the best - if pricy - atmospheric to orbit shuttles and gliders for the consumer market."),
		"aether" = list(LIGHT_COLOR_CYAN, "Aether Atmospherics, one of the lesser-known TSCs. They're ubiquitious in the Periphery - the very air you're breathing was probably sold and delivered by them."),
		"moreau" = list(LIGHT_COLOR_ORANGE, "Children of Moreau. The hologram is a call to action by the local Moreau sect. 'Terraform, Prosper, and Be Sustainable, children!'"),
		"cybersun" = list(LIGHT_COLOR_GREEN, "Cybersun Industries. A complex diagram without labels, showing the inner workings of a backup implant sold by Cybersun. 'The highest quality, for an affordable price!' says the tagline."),
		"veymed" = list(LIGHT_COLOR_GREEN, "Vey-Med. This is an advertisement for a local clinic a few systems away. The tagline reads 'The mark of a truly civilized civilization is rewriting what evolution could not'."),
		"grayson" = list(LIGHT_COLOR_ORANGE, "Grayson Manufactories Ltd. An advertisement for a sale from Grayson, including up to 50% off on lathe parts. Truly, a delight for DIY tinkerers out there."),
		"ares" = list(LIGHT_COLOR_PINK, "Friends of Ares. Who managed to slip this poster into the rotation? A local charity set up by the Ares Confederation to help workers unionize or found their own colonies. 'Donate today!'"),
		"moebius" = list(LIGHT_COLOR_PURPLE, "Moebius. One of the few companies worth merit beyond their local bubble staffed completely by synthetics. 'For synths, by synths.'")
	)

REGISTRY_MEMBERSHIP(/obj/machinery/holoposter, REGISTRY_HOLOPOSTERS)

/obj/machinery/holoposter/Initialize(mapload)
	. = ..()
	set_rand_sprite()
	schedule_rotation()

/// The next random poster, 30 to 35 minutes out, on the machine clock.
/obj/machinery/holoposter/proc/schedule_rotation()
	after(src, 30 MINUTES + rand(0, 5 MINUTES), PROC_REF(rotate_sprite), key = "holoposter_rotation")

/obj/machinery/holoposter/proc/rotate_sprite()
	if(icon_forced)
		return
	set_rand_sprite()
	schedule_rotation()

/obj/machinery/holoposter/examine(mob/user, infix, suffix)
	. = ..()
	. += examine_addon

DECLARE_APPEARANCE_PROC(/obj/machinery/holoposter, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/holoposter/appearance_overlays()
	. = list()
	if(power_lost())
		icon_state = "off"
		examine_addon = "It appears to be powered off."
		set_light(0)
		return .
	var/new_color = LIGHT_COLOR_HALOGEN
	if(broken_now())
		icon_state = "glitch"
		examine_addon = "It appears to be malfunctioning."
		new_color = "#6A6C71"
	else
		if((z in using_map.station_levels) && GLOB.security_level) // 0 is fine, everything higher is alert levels
			icon_state = "attention"
			examine_addon = "It warns you to remain calm and contact your supervisor as soon as possible."
			new_color =  "#AA7039"
			alerting = TRUE
		else if(alerting && !GLOB.security_level) // coming out of alert
			alerting = FALSE
			set_rand_sprite()
			return .
		else if(icon_state in postertypes)
			var/list/settings = postertypes[icon_state]
			new_color = settings[1]
			examine_addon = settings[2]

	set_light(l_range = 2, l_power = 2, l_color = new_color)

/obj/machinery/holoposter/proc/set_rand_sprite()
	if(alerting)
		return
	if(icon_forced)
		return
	icon_state = pick(postertypes)
	update_icon()

/// The multitool works a powered poster (an unpowered one takes the click and does nothing).
/obj/machinery/holoposter/proc/is_powered(datum/act/op/A)
	return !power_lost()

/// The posters the multitool's question offers.
/obj/machinery/holoposter/proc/poster_choices(datum/act/A)
	return postertypes + "random"

/// The multitool's answer: that poster, or random rotation.
/obj/machinery/holoposter/proc/poster_chosen(datum/act/op/A)
	add_fingerprint(A.actor)
	play_sfx(src, SFX_ITEMS_PENCLICK, 1.2)
	var/choice = A.answer?.value
	if(!choice || power_lost())
		return OP_OK
	icon_state = choice
	if(icon_state == "random")
		atom_fix()
		icon_forced = FALSE
		schedule_rotation()
		set_rand_sprite()
		return OP_OK
	icon_forced = TRUE
	cancel_after(src, "holoposter_rotation")
	atom_fix()
	update_icon()
	return OP_OK

CAPABILITIES(/obj/machinery/holoposter)
	extend(/datum/act/hit/emp, instead(then(PROC_REF(holoposter_emp))))
	op("use_multitool", tool(TOOL_MULTITOOL), priority(OP_PRIORITY_DEFAULT), wait(0), label("Choose poster"), needs(req(PROC_REF(is_powered), silent = TRUE)),
		asks(/datum/prompt/choice, fields = list("question" = "Available Posters", "title" = "Holographic Poster", "choices" = computed(PROC_REF(poster_choices)), "timeout" = 0)),
		then(PROC_REF(poster_chosen)))

/// An EMP breaks the poster.
/obj/machinery/holoposter/proc/holoposter_emp(datum/act/hit/emp/A)
	if(broken_now())
		return HOOK_DECLINE
	atom_break()
	return HOOK_DECLINE
