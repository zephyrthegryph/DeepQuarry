//wip wip wup
/obj/structure/mirror
	name = "mirror"
	desc = "A SalonPro Nano-Mirror(TM) brand mirror! The leading technology in hair salon products, utilizing nano-machinery to style your hair just right."
	icon = 'icons/obj/watercloset.dmi'
	icon_state = "mirror"
	layer = ABOVE_WINDOW_LAYER
	density = FALSE
	anchored = TRUE
	flags = WALL_ITEM
	var/shattered = 0
	var/glass = 1
	var/datum/tgui_module/appearance_changer/mirror/M

/obj/structure/mirror/Initialize(mapload, dir, building = 0)
	. = ..()
	M = new(src, null)
	if(building)
		glass = 0
		icon_state = "mirror_frame"
		pixel_x = (dir & 3)? 0 : (dir == 4 ? -28 : 28)
		pixel_y = (dir & 3)? (dir == 1 ? -30 : 30) : 0

DECLARE_REF(/obj/structure/mirror, "M", OWNED, null)

/obj/structure/mirror/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_hand/mirror_open_ui,
		/datum/interaction/entry_item/mirror_item,
	)
	into += dq_interaction_from_spec(type, INTERACT_SILICON("Use", PROC_REF(mirror_silicon_use)))
	..()

/// Old attack_hand: open the appearance changer.
/datum/interaction/entry_hand/mirror_open_ui
	id = "mirror_open_ui"
	name = "Use"
	effect = /obj/structure/mirror/proc/mirror_open_ui

/obj/structure/mirror/proc/mirror_open_ui(mob/user, obj/item/held, datum/interaction/interaction)
	if(!glass) return TRUE
	if(shattered)	return TRUE

	M.tgui_interact(user)
	return TRUE

/// Old attack_ai: a silicon next to it opens the appearance changer.
/obj/structure/mirror/proc/mirror_silicon_use(mob/user, obj/item/held, datum/interaction/interaction)
	if(!glass) return TRUE
	if(shattered)	return TRUE
	if(!Adjacent(user)) return TRUE

	M.tgui_interact(user)
	return TRUE

/obj/structure/mirror/proc/shatter()
	if(!glass) return
	if(shattered)	return
	shattered = 1
	icon_state = "mirror_broke"
	play_sfx(src, SFX_SHATTER)
	desc = "Oh no, seven years of bad luck!"

/obj/structure/mirror/bullet_act(obj/item/projectile/Proj)

	if(prob(Proj.get_structure_damage() * 2))
		if(!shattered)
			shatter()
		else if(glass)
			play_sfx(src, SFX_EFFECTS_HIT_ON_SHATTERED_GLASS)
	..()

/// Old attackby: re-glaze with two sheets of glass, or smash it.
/datum/interaction/entry_item/mirror_item
	id = "mirror_item"
	name = "Use"
	effect = /obj/structure/mirror/proc/interaction_item

/obj/structure/mirror/proc/interaction_item(mob/user, obj/item/I, datum/interaction/interaction)
	if(istype(I, /obj/item/stack/material/glass))
		if(!glass)
			var/obj/item/stack/material/glass/G = I
			if (G.get_amount() < 2)
				to_chat(user, span_warning("You need two sheets of glass to add them to the frame."))
				return TRUE
			to_chat(user, span_notice("You start to add the glass to the frame."))
			om_task_timed(user, 2 SECONDS, target = src, receiver = src, on_done = PROC_REF(attackby_timed_done), done_args = list(user, G))
			return TRUE

	if(shattered && glass)
		play_sfx(src, SFX_EFFECTS_HIT_ON_SHATTERED_GLASS)
		return TRUE

	if(prob(I.force * 2))
		act_message(user, src, others = span_warning("%U% smashes %T% with [I]!"))
		if(glass)
			shatter()
	else
		act_message(user, src, others = span_warning("%U% hits %T% with [I]!"))
		play_sfx(src, SFX_EFFECTS_GLASSHIT, volume = 70)
	return TRUE

/obj/structure/mirror/proc/attackby_timed_done(mob/user, obj/item/stack/material/glass/G)
	if (G.use(2))
		shattered = 0
		glass = 1
		icon_state = "mirror"
		to_chat(user, span_notice("You add the glass to the frame."))

/obj/structure/mirror/wrench_act(mob/user, obj/item/I)
	if(!glass)
		use_tool(user, I, src, delay = 2 SECONDS, quality = TOOL_WRENCH, volume = 50, receiver = src, on_done = PROC_REF(wrench_act_tool_done), done_args = list(user))
		return TRUE
	if(shattered)
		to_chat(user, span_notice("The broken glass falls out."))
		icon_state = "mirror_frame"
		glass = FALSE
		new /obj/item/material/shard(loc)
		return TRUE
	playsound(src, I.usesound, 50, 1)
	to_chat(user, span_notice("You remove the glass."))
	glass = FALSE
	icon_state = "mirror_frame"
	new /obj/item/stack/material/glass(loc, 2)
	return TRUE

/obj/structure/mirror/proc/wrench_act_tool_done(mob/user)
	to_chat(user, span_notice("You unfasten the frame."))
	replace_with(src, /obj/item/frame/mirror)

/obj/structure/mirror/attack_generic(mob/user, damage)

	user.do_attack_animation(src)
	if(shattered && glass)
		play_sfx(src, SFX_EFFECTS_HIT_ON_SHATTERED_GLASS)
		return 0

	if(damage)
		act_message(user, src, others = span_danger("%U% smashes %T%!"))
		if(glass)
			shatter()
	else
		act_message(user, src, others = span_danger("%U% hits %T% and bounces off!"))
	return 1

// The following mirror is ~special~.
/obj/structure/mirror/raider
	name = "cracked mirror"
	desc = "Something seems strange about this old, dirty mirror. Your reflection doesn't look like you remember it."
	icon_state = "mirror_broke"
	shattered = 1

/// Overrides mirror's mirror_open_ui(): raiders may become Vox here, then the mirror opens as usual.
/obj/structure/mirror/raider/mirror_open_ui(mob/living/carbon/human/user, obj/item/held, datum/interaction/interaction)
	if(istype(get_area(src),/area/syndicate_mothership))
		if(istype(user) && user.mind && user.mind.special_role == "Raider" && user.species.name != SPECIES_VOX && is_alien_whitelisted(user.client, SPECIES_VOX))
			om_ask(user, /datum/om/prompt/confirm, PROC_REF(become_vox_answered), title = "Become Vox?", message = "Do you wish to become a true Vox of the Shoal? This is not reversible.", no_first = TRUE, ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE)
	return ..()

/obj/structure/mirror/raider/proc/become_vox_answered(datum/om/prompt/confirm/ask)
	var/mob/living/carbon/human/user = ask.answerer
	var/mob/living/carbon/human/vox/vox = new(get_turf(src),SPECIES_VOX)
	vox.gender = user.gender
	GLOB.raiders.equip(vox)
	if(user.mind)
		user.mind.transfer_to(vox)
	om_ask(vox, /datum/om/prompt/text, TYPE_PROC_REF(/mob/living/carbon/human, raider_vox_named), receiver = vox, title = "Name change", message = "Enter a name, or leave blank for the default name.", default = "", max_length = MAX_NAME_LEN, encode = FALSE, cancel_answer = "")
	qdel(user)

/mob/living/carbon/human/proc/raider_vox_named(datum/om/prompt/text/ask)
	var/mob/living/carbon/human/vox = src
	var/newname = sanitizeSafe(ask.text, MAX_NAME_LEN)
	if(!newname || newname == "")
		var/datum/language/L = GLOB.all_languages[vox.species.default_language]
		newname = L.get_random_name()
	vox.real_name = newname
	vox.name = vox.real_name
	GLOB.raiders.update_access(vox)
