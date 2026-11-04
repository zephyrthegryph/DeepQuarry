/////////
//CHEAP//
/////////
/obj/item/flame/lighter
	name = "cheap lighter"
	desc = "A cheap-as-free lighter."
	icon = 'icons/obj/lighters.dmi'
	icon_state = "lighter"
	item_state = "lighter"
	w_class = ITEMSIZE_TINY
	var/base_state
	/// Sounds
	var/activation_sound = SFX_ITEMS_LIGHTER_ON
	var/deactivation_sound = SFX_ITEMS_LIGHTER_OFF
	/// Color of the flame and how big the flame is (pulled from Welder code)
	var/flame_color = "#FF9933"
	var/flame_intensity = 2
	/// Color List
	var/random_color = FALSE
	var/available_colors = list(COLOR_ASSEMBLY_BLACK,
								COLOR_ASSEMBLY_BGRAY,
								COLOR_ASSEMBLY_WHITE,
								COLOR_ASSEMBLY_RED,
								COLOR_ASSEMBLY_ORANGE,
								COLOR_ASSEMBLY_BEIGE,
								COLOR_ASSEMBLY_BROWN,
								COLOR_ASSEMBLY_GOLD,
								COLOR_ASSEMBLY_YELLOW,
								COLOR_ASSEMBLY_GURKHA,
								COLOR_ASSEMBLY_LGREEN,
								COLOR_ASSEMBLY_GREEN,
								COLOR_ASSEMBLY_LBLUE,
								COLOR_ASSEMBLY_BLUE,
								COLOR_ASSEMBLY_PURPLE,
								COLOR_ASSEMBLY_HOT_PINK)
	/// If we are a special variant (see: override attack_self)
	var/special_variant = FALSE
	/// Var used for detonator zippos

/// Var used for detonator zippos
/obj/item/flame/lighter/var/detonator_mode = 0

CAPABILITIES(/obj/item/flame/lighter)
	configure(atom_rules(price_tag = 2, description_fluff = "The 'hand-made in Altair' sticker underneath is a charming way of \
	saying 'Made with prison labour'. It's no wonder the company can sell these things so cheap."))
	configure(item_handling(cavity_implantable = FALSE))
	configure(item_worn(slots = SLOT_BELT))
	configure(item_thrown(force = 4))
	configure(item_combat(attack_verbs = list("burnt", "singed")))
	op("toggle", in_hand(), then(PROC_REF(toggled)))
	rolls(nameof(cheap_pattern), PROC_REF(roll_cheap_pattern))
	rolls(nameof(cheap_color), PROC_REF(roll_cheap_color))

// TODO: Remove this path from POIs and loose maps (it's no longer needed)
/obj/item/flame/lighter/random

/// A cheap lighter wears a random pattern and colour, rolled when it spawns (a zippo does not).
/obj/item/flame/lighter/var/cheap_look = TRUE

/obj/item/flame/lighter/var/cheap_pattern

/obj/item/flame/lighter/var/cheap_color

/// Rolled before init (rolls()): a cheap lighter's pattern; a zippo has none.
/obj/item/flame/lighter/proc/roll_cheap_pattern(datum/roller/R)
	if(!cheap_look)
		return null
	return "lighter-[R.choose(list("trans", "tall", "matte"))]"

/// Rolled before init (rolls()): a cheap lighter's colour; a zippo has none.
/obj/item/flame/lighter/proc/roll_cheap_color(datum/roller/R)
	if(!cheap_look)
		return null
	return R.choose(available_colors)

/obj/item/flame/lighter/draw(datum/look/look)
	..()
	look.overlay(look_overlay_image(icon, cheap_pattern, color = cheap_color), when = !isnull(cheap_pattern))

/// Using the lighter in the hand lights it or puts it out. Each kind of lighter overrides this; one that does not handle the use declines it, and the click goes on to the item's own use.
/obj/item/flame/lighter/proc/toggled(datum/act/op/A)
	var/mob/living/user = A.actor
	if(special_variant)
		return OP_DECLINE
	if(detonator_mode)
		return OP_DECLINE
	if(!lit)
		set_lit(TRUE)
		set_icon_state("lighteron")
		playsound(src, activation_sound, 75, 1)
		act_message(user, src, others = span_notice("After a few attempts, %U% manages to light %T%."))

		set_glow(src, GLOW(2, 0.5, "#FF9933"))
	else
		set_lit(FALSE)
		set_icon_state("lighter")
		playsound(src, deactivation_sound, 75, 1)
		act_message(user, src, others = span_notice("%U% quietly shuts off %T%."))

		set_glow(src, GLOW(0, null, null))
	return OP_OK

/obj/item/flame/lighter/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(lit == 1)
		M.ignite_mob()
		add_attack_logs(user,M,"Lit on fire with [src]")
		return ITEM_INTERACT_SUCCESS

	if(istype(M.get_equipped_item(SLOT_ID_MASK), /obj/item/clothing/mask/smokable/cigarette) && hud_of(user)?.zone_sel?.selecting == O_MOUTH && lit)
		var/obj/item/clothing/mask/smokable/cigarette/cig = M.get_equipped_item(SLOT_ID_MASK)
		if(M == user)
			cig.attackby(src, user)
			return ITEM_INTERACT_SUCCESS

		else
			if(istype(src, /obj/item/flame/lighter/zippo))
				cig.light(span_notice(span_rose("[user] whips the [name] out and holds it for [M].")), user)
			else
				cig.light(span_notice("[user] holds the [name] out for [M], and lights the [cig.name]."), user)
			return ITEM_INTERACT_SUCCESS
	else
		..()

/obj/item/flame/lighter/flame_step(datum/act/timer/A)
	var/turf/location = get_turf(src)
	if(location)
		location.hotspot_expose(700, 5)
	return
