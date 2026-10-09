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

TRACKED(/obj/structure/mirror, glass)

CAPABILITIES(/obj/structure/mirror)
	owns_one(nameof(M), /datum/tgui_module/appearance_changer/mirror)
	op("use_wrench", tool(TOOL_WRENCH), wait(0), then(PROC_REF(wrench_used)))
	op("use", hand(), label("Use"), then(PROC_REF(mirror_open_ui)))
	op("silicon_use", remote(), label("Use"), needs(req_adjacent()), then(PROC_REF(mirror_open_ui)))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))
	op("add_glass", stack(/obj/item/stack/material/glass, 2), label("Add glass"), when(req_bool(PROC_REF(frame_empty))), begins(MSG(mirror/adding_glass)), wait(2 SECONDS), then(PROC_REF(glass_added)))
	param(nameof(dir), pos = 1)
	param(nameof(building), pos = 2)

/// A mirror built on a wall (its constructor param).
/obj/structure/mirror/var/building = FALSE

// ALLOW(init/INSTANCE_STATE): a mirror makes its appearance changer, and a built one is an empty frame on its wall
/obj/structure/mirror/Initialize(mapload)
	. = ..()
	rel_set(src, nameof(M), new /datum/tgui_module/appearance_changer/mirror(src, null))
	if(building)
		set_glass(0)
		icon_state = "mirror_frame"
		pixel_x = (dir & 3)? 0 : (dir == 4 ? -28 : 28)
		pixel_y = (dir & 3)? (dir == 1 ? -30 : 30) : 0


/// A hand, or a silicon beside it: the appearance changer, while the glass is whole.
/obj/structure/mirror/proc/mirror_open_ui(datum/act/op/A)
	if(!glass || shattered)
		return OP_OK
	M.tgui_interact(A.actor)
	return OP_OK

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

/obj/structure/mirror/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	if(istype(I, /obj/item/stack/material/glass) && !glass)
		return OP_OK // too few sheets to add the glass (add_glass takes two)

	if(shattered && glass)
		play_sfx(src, SFX_EFFECTS_HIT_ON_SHATTERED_GLASS)
		return OP_OK

	if(prob(I.force * 2))
		act_message(user, src, others = span_warning("%U% smashes %T% with [I]!"))
		if(glass)
			shatter()
	else
		act_message(user, src, others = span_warning("%U% hits %T% with [I]!"))
		play_sfx(src, SFX_EFFECTS_GLASSHIT, volume = 70)
	return OP_OK

MSG_DEF_SELF(mirror/adding_glass, span_notice("You start to add the glass to the frame."))

/// A frame without glass takes it.
/obj/structure/mirror/proc/frame_empty(datum/act/op/A)
	return !glass

/obj/structure/mirror/proc/glass_added(datum/act/op/A)
	shattered = 0
	set_glass(1)
	icon_state = "mirror"
	to_chat(A.actor, span_notice("You add the glass to the frame."))

/obj/structure/mirror/proc/wrench_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	if(!glass)
		use_tool(user, I, src, delay = 2 SECONDS, quality = TOOL_WRENCH, volume = 50, receiver = src, on_done = PROC_REF(wrench_act_tool_done), done_args = list(user))
		return OP_OK
	if(shattered)
		to_chat(user, span_notice("The broken glass falls out."))
		icon_state = "mirror_frame"
		set_glass(FALSE)
		new /obj/item/material/shard(loc)
		return OP_OK
	playsound(src, I.usesound, 50, 1)
	to_chat(user, span_notice("You remove the glass."))
	set_glass(FALSE)
	icon_state = "mirror_frame"
	new /obj/item/stack/material/glass(loc, 2)
	return OP_OK

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
			open_request(src, /datum/prompt/yes_no, PROC_REF(become_vox_answered), answerer = user, title = "Become Vox?", question = "Do you wish to become a true Vox of the Shoal? This is not reversible.", ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE, timeout = 0)
	return ..()

/obj/structure/mirror/raider/proc/become_vox_answered(datum/act/request/A)
	if(!A.answer || !A.answer.value)
		return
	var/mob/living/carbon/human/user = A.request.answerer
	var/mob/living/carbon/human/vox/vox = new(get_turf(src),SPECIES_VOX)
	vox.gender = user.gender
	GLOB.raiders.equip(vox)
	if(user.mind)
		user.mind.transfer_to(vox)
	open_request(vox, /datum/prompt/text, TYPE_PROC_REF(/mob/living/carbon/human, raider_vox_named), answerer = vox, title = "Name change", question = "Enter a name, or leave blank for the default name.", default = "", max_len = MAX_NAME_LEN, name_text = TRUE, encode = FALSE, timeout = 0)
	spent(user)

/// The new vox is named: a closed window is the blank name, which is the default one.
/mob/living/carbon/human/proc/raider_vox_named(datum/act/request/A)
	var/mob/living/carbon/human/vox = src
	var/newname = sanitizeSafe(A.answer ? A.answer.value : "", MAX_NAME_LEN)
	if(!newname || newname == "")
		var/datum/language/L = GLOB.all_languages[vox.species.default_language]
		newname = L.get_random_name()
	vox.real_name = newname
	vox.name = vox.real_name
	GLOB.raiders.update_access(vox)
