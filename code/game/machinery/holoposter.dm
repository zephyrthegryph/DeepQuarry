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
	om_after_replace(src, 30 MINUTES + rand(0, 5 MINUTES), PROC_REF(rotate_sprite))

/obj/machinery/holoposter/proc/rotate_sprite()
	if(icon_forced)
		return
	set_rand_sprite()
	schedule_rotation()

/obj/machinery/holoposter/examine(mob/user, infix, suffix)
	. = ..()
	. += examine_addon

/obj/machinery/holoposter/update_icon()
	if(has_stat(NOPOWER))
		icon_state = "off"
		examine_addon = "It appears to be powered off."
		set_light(0)
		return
	var/new_color = LIGHT_COLOR_HALOGEN
	if(has_stat(BROKEN))
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
			return
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

/obj/machinery/holoposter/multitool_act(mob/user, obj/item/tool)
	src.add_fingerprint(user)
	if(has_stat(NOPOWER))
		return ITEM_INTERACT_BLOCKING
	playsound(src, 'sound/items/penclick.ogg', 60, TRUE)
	om_ask(user, /datum/om/prompt/choice, PROC_REF(poster_chosen), message = "Available Posters", title = "Holographic Poster", choices = postertypes + "random", requires = PROMPT_ADJACENT)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/holoposter/proc/poster_chosen(datum/om/prompt/choice/ask)
	var/choice = ask.choice
	if(has_stat(NOPOWER))
		return
	icon_state = choice
	if(icon_state == "random")
		atom_fix()
		icon_forced = FALSE
		schedule_rotation()
		set_rand_sprite()
		return ITEM_INTERACT_SUCCESS
	icon_forced = TRUE
	om_cancel_calls(src, PROC_REF(rotate_sprite))
	atom_fix()
	update_icon()
	return ITEM_INTERACT_SUCCESS

/obj/machinery/holoposter/power_change()
	var/wasUnpowered = has_stat(NOPOWER)
	. = ..()
	if(wasUnpowered != (has_stat(NOPOWER)))
		update_icon()

/obj/machinery/holoposter/emp_act(severity, recursive)
	. = ..()
	if (. & EMP_PROTECT_SELF || has_stat(BROKEN))
		return
	atom_break()
