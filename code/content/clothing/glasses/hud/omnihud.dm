//Omnihuds
/obj/item/clothing/glasses/omnihud
	name = "\improper AR glasses"
	desc = "The ARG-62 AR Glasses are capable of displaying information on individuals. \
	Commonly used to allow non-augmented crew to interact with virtual interfaces. \
	<br>They are also fitted with toggleable cosmetic electrochromic lenses. \
	The lenses will not protect against sudden bright flashes or welding."
	var/mode = "civ"
	icon_state = "glasses"
	var/datum/tgui_module/tgarscreen
	/// The AR screen while an EMP has it offline (owned; reconnect_tgar() moves it back).
	var/datum/tgui_module/offline_tgarscreen
	var/tgarscreen_path
	var/flash_prot = 0 //0 for none, 1 for flash weapon protection, 2 for welder protection
	enables_planes = list(VIS_CH_ID,VIS_CH_HEALTH_VR,VIS_AUGMENTED)
	plane_slots = list(SLOT_ID_EYES)
	var/ar_toggled = TRUE //Used for toggle_ar_planes() verb
	var/can_shade = TRUE
	specialty_goggles = TRUE
	var/hud_goggles = FALSE

CAPABILITIES(/obj/item/clothing/glasses/omnihud)
	owns_one(nameof(tgarscreen), starts = nameof(tgarscreen_path))
	owns_one(nameof(offline_tgarscreen), /datum/tgui_module)
	op("omnihud_display_self", in_hand(), then(PROC_REF(omnihud_display_self)))
	op("omnihud_chromatize_verb", menu(), label("Toggle AR Glasses Shading"), needs(carried()), then(PROC_REF(omnihud_chromatize_verb)))
	op("omnihud_toggle_ar_planes_verb", menu(), label("Toggle AR Heads-Up Display"), needs(carried()), then(PROC_REF(omnihud_toggle_ar_planes_verb)))
	on_notice(/datum/notice/hit/emp, then(PROC_REF(omnihud_emp_disconnect)))

/obj/item/clothing/glasses/omnihud/dropped(mob/user, equipping, slot)
	if(tgarscreen)
		SStgui.close_uis(src)
	..()

/obj/item/clothing/glasses/omnihud/examine()
	. = ..()
	if(ar_toggled)
		. += "\n " + span_notice("The HUD indicator reads ON.")
	else
		. += "\n " + span_notice("The HUD indicator reads OFF.")

/// after() target: the AR screen comes back after an EMP.
/obj/item/clothing/glasses/omnihud/proc/reconnect_tgar()
	if(offline_tgarscreen && !tgarscreen)
		rel_move(src, nameof(offline_tgarscreen), src, nameof(tgarscreen))

/// A pulse drops the AR link for a while (and can glitch the lenses).
/obj/item/clothing/glasses/omnihud/proc/omnihud_emp_disconnect(datum/act/A)
	if(tgarscreen)
		SStgui.close_uis(src)
	if(tgarscreen && !offline_tgarscreen)
		rel_move(src, nameof(tgarscreen), src, nameof(offline_tgarscreen))
		after(src, 20 SECONDS, PROC_REF(reconnect_tgar))

	//extra fun for non-sci variants; a small chance flip the state to the dumb 3d glasses when EMP'd
	if(icon_state == "glasses" || icon_state == "sun")
		if(prob(10))
			set_icon_state("3d")
			if(ishuman(loc))
				to_chat(loc, span_warning("The lenses of your [src.name] malfunction!"))

/obj/item/clothing/glasses/omnihud/proc/flashed()
	if(flash_prot && ishuman(loc))
		to_chat(loc, span_warning("Your [src.name] darken to try and protect your eyes!"))

/obj/item/clothing/glasses/omnihud/prescribe(mob/user)
	prescription = !prescription
	play_sfx(src, SFX_ITEMS_SCREWDRIVER)
	if(prescription)
		act_message(user, null, others = "%U% uploads new prescription data to the [src.name] and resets the lenses.")
		name = "[initial(name)] (pr)" //change the name *after* the text so the message above is accurate
		set_icon_state("[initial(icon_state)]") //reset the icon state just to be safe
	else
		act_message(user, null, others = "%U% deletes the prescription data on the [src.name] and resets the lenses.")
		name = "[initial(name)]"
		set_icon_state("[initial(icon_state)]")

/// Old attack_self: show the AR display. FALSE where the old body fell through or returned nothing.
/obj/item/clothing/glasses/omnihud/proc/omnihud_display_self(datum/act/op/A)
	var/mob/user = A.actor
	if(!ishuman(user))
		return OP_DECLINE
	if(hud_goggles)
		return OP_DECLINE

	var/mob/living/carbon/human/H = user
	if(!H.get_equipped_item(SLOT_ID_EYES) || !(H.get_equipped_item(SLOT_ID_EYES) == src))
		to_chat(user, span_warning("You must be wearing the [src] to see the display."))
	else
		if(!ar_interact(H))
			to_chat(user, span_warning("The [src] does not have any kind of special display."))
	return OP_DECLINE

//cosmetic shading, doesn't enhance eye protection
/// Old verb "Toggle AR Glasses Shading".
/obj/item/clothing/glasses/omnihud/proc/omnihud_chromatize_verb(datum/act/op/A)
	var/mob/user = A.actor
	if(!user.canmove || user.stat || user.restrained())
		return
	if(icon_state == "3d")
		to_chat(user, "You reset the electrochromic lenses of \the [src] back to normal.")
		if(prescription)
			name = "[initial(name)] (pr)"
		else
			name = "[initial(name)]"
		set_icon_state("[initial(icon_state)]")
	else if(prescription)
		if(icon_state == "glasses")
			to_chat(user, "You darken the electrochromic lenses of \the [src] to one-way transparency.")
			name = "[initial(name)] (shaded, pr)"
			set_flags_inv(worn_of(src).hides | (HIDEEYES))
			set_icon_state("sun")
		else if(icon_state == "sun")
			to_chat(user, "You restore the electrochromic lenses of \the [src] to standard two-way transparency.")
			name = "[initial(name)] (pr)"
			set_flags_inv(worn_of(src).hides & (~HIDEEYES))
			set_icon_state("glasses")
		else
			to_chat(user, "It doesn't seem possible to do that with \the [src].")
	else if(!prescription)
		if(icon_state == "glasses")
			to_chat(user, "You darken the electrochromic lenses of \the [src] to one-way transparency.")
			name = "[initial(name)] (shaded)"
			set_flags_inv(worn_of(src).hides | (HIDEEYES))
			set_icon_state("sun")
		else if(icon_state == "sun")
			to_chat(user, "You restore the electrochromic lenses of \the [src] to standard two-way transparency.")
			name = "[initial(name)]"
			set_flags_inv(worn_of(src).hides & (~HIDEEYES))
			set_icon_state("glasses")
		else
			to_chat(user, "It doesn't seem possible to do that with \the [src].")
	else if(!can_shade)
		to_chat(user, "It doesn't seem possible to do that with \the [src].")

/// Old verb "Toggle AR Heads-Up Display".
/obj/item/clothing/glasses/omnihud/proc/omnihud_toggle_ar_planes_verb(datum/act/op/A)
	var/mob/user = A.actor
	//We do not check if user can move or not, since this system is inspired to help see chat bubbles during scenes primarily.
	//Preventing turning off the HUD could get in the way of scene flow.
	if(ar_toggled)
		away_planes = enables_planes
		enables_planes = null
		to_chat(user, span_notice("You disable the Augmented Reality HUD of your [src.name]."))
	else
		enables_planes = away_planes
		away_planes = null
		to_chat(user, span_notice("You enable the Augmented Reality HUD of your [src.name]."))
	ar_toggled = !ar_toggled
	user.update_mob_action_buttons()
	user.recalculate_vis()

/obj/item/clothing/glasses/omnihud/proc/ar_interact(mob/living/carbon/human/user)
	return 0 //The base models do nothing.

/obj/item/clothing/glasses/omnihud/visor
	name = "AR visor"
	desc = "The VZR-AR are a product based upon the classic AR Glasses, just more fashionable."
	icon = 'icons/inventory/eyes/mob.dmi'
	icon_state = "visor_CIV"
	item_state = "visor_CIV"

	can_shade = FALSE

/obj/item/clothing/glasses/omnihud/rnd
	name = "\improper AR-R glasses"
	desc = "The ARG-62-R AR Glasses are capable of displaying information on individuals. \
	They... don't seem to do anything particularly interesting? But hey, at least they look kinda science-y."
	mode = "sci"

/obj/item/clothing/glasses/omnihud/rnd/prescription
	desc = "The ARG-62-R AR Glasses are capable of displaying information on individuals. \
	They... don't seem to do anything particularly interesting? But hey, at least they look kinda science-y. \
	These have been equipped with prescription lenses."
	prescription = TRUE

/obj/item/clothing/glasses/omnihud/prescription
	desc = "The ARG-62 AR Glasses are capable of displaying information on individuals. \
	Commonly used to allow non-augmented crew to interact with virtual interfaces. \
	<br>They are also fitted with toggleable cosmetic electrochromic lenses. \
	The lenses will not protect against sudden bright flashes or welding. \
	These have been equipped with prescription lenses."
	prescription = TRUE
