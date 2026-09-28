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

REF_OWNED(/obj/structure/mirror, "M")

/obj/structure/mirror/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_hand/mirror_open_ui,
		/datum/interaction/entry_item/mirror_item,
	)
	..()

/// Old attack_hand: open the appearance changer.
/datum/interaction/entry_hand/mirror_open_ui
	id = "mirror_open_ui"
	name = "Use"
	effect = /obj/structure/mirror/proc/interaction_open_ui

/obj/structure/mirror/proc/interaction_open_ui(mob/user, obj/item/held, datum/interaction/interaction)
	if(!glass) return TRUE
	if(shattered)	return TRUE

	M.tgui_interact(user)
	return TRUE

/obj/structure/mirror/attack_ai(mob/user)
	if(!glass) return
	if(shattered)	return
	if(!Adjacent(user)) return

	M.tgui_interact(user)

/obj/structure/mirror/proc/shatter()
	if(!glass) return
	if(shattered)	return
	shattered = 1
	icon_state = "mirror_broke"
	playsound(src, "shatter", 70, 1)
	desc = "Oh no, seven years of bad luck!"

/obj/structure/mirror/bullet_act(obj/item/projectile/Proj)

	if(prob(Proj.get_structure_damage() * 2))
		if(!shattered)
			shatter()
		else if(glass)
			playsound(src, 'sound/effects/hit_on_shattered_glass.ogg', 70, 1)
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
			om_do_after(user, 2 SECONDS, target = src, receiver = src, on_done = PROC_REF(attackby_timed_done), done_args = list(user, G))
			return TRUE

	if(shattered && glass)
		playsound(src, 'sound/effects/hit_on_shattered_glass.ogg', 70, 1)
		return TRUE

	if(prob(I.force * 2))
		visible_message(span_warning("[user] smashes [src] with [I]!"))
		if(glass)
			shatter()
	else
		visible_message(span_warning("[user] hits [src] with [I]!"))
		playsound(src, 'sound/effects/Glasshit.ogg', 70, 1)
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
		playsound(src, 'sound/effects/hit_on_shattered_glass.ogg', 70, 1)
		return 0

	if(damage)
		user.visible_message(span_danger("[user] smashes [src]!"))
		if(glass)
			shatter()
	else
		user.visible_message(span_danger("[user] hits [src] and bounces off!"))
	return 1

// The following mirror is ~special~.
/obj/structure/mirror/raider
	name = "cracked mirror"
	desc = "Something seems strange about this old, dirty mirror. Your reflection doesn't look like you remember it."
	icon_state = "mirror_broke"
	shattered = 1

/// Overrides mirror's interaction_open_ui(): raiders may become Vox here, then the mirror opens as usual.
/obj/structure/mirror/raider/interaction_open_ui(mob/living/carbon/human/user, obj/item/held, datum/interaction/interaction)
	if(istype(get_area(src),/area/syndicate_mothership))
		if(istype(user) && user.mind && user.mind.special_role == "Raider" && user.species.name != SPECIES_VOX && is_alien_whitelisted(user.client, SPECIES_VOX))
			om_prompt(src, user, list("message" = "Do you wish to become a true Vox of the Shoal? This is not reversible.", "title" = "Become Vox?", "choices" = list("No","Yes"), "requires" = PROMPT_ADJACENT), PROC_REF(become_vox_answered))
	return ..()

/obj/structure/mirror/raider/proc/become_vox_answered(mob/living/carbon/human/user, choice, datum/om/prompt/ask)
	if(choice != "Yes")
		return
	var/mob/living/carbon/human/vox/vox = new(get_turf(src),SPECIES_VOX)
	vox.gender = user.gender
	GLOB.raiders.equip(vox)
	if(user.mind)
		user.mind.transfer_to(vox)
	om_prompt(vox, vox, list("kind" = "text", "message" = "Enter a name, or leave blank for the default name.", "title" = "Name change", "default" = "", "max_length" = MAX_NAME_LEN, "encode" = FALSE, "on_cancel" = GLOBAL_PROC_REF(raider_vox_named)), GLOBAL_PROC_REF(raider_vox_named))
	qdel(user)

/proc/raider_vox_named(mob/living/carbon/human/vox, mob/user, newname, datum/om/prompt/ask)
	if(istype(newname, /datum/om/prompt))
		newname = null
	newname = sanitizeSafe(newname, MAX_NAME_LEN)
	if(!newname || newname == "")
		var/datum/language/L = GLOB.all_languages[vox.species.default_language]
		newname = L.get_random_name()
	vox.real_name = newname
	vox.name = vox.real_name
	GLOB.raiders.update_access(vox)
