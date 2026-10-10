/*
Remote scene tools! These, in effects, serve 2 purposes:

* Forward emotes from wearer of one to wearer of its partner
* Provide simple feedback - is your partner dead, SSD, did they log out? - some are more explicit.

why aren't these accessories?
	They easily could be! I'm just lazy and don't wanna forward the "see emote" from wearables to all the accessories

*/

/obj/item/remote_scene_tool/get_mechanics_info(list/additional_information)
	return ..(list("Emotes and subtles the wearer does go directly to the linked tool; only its wearer sees them, and they must be wearing, holding or pocketing it. Remember bystander consent!") + additional_information)

/obj/item/remote_scene_tool
	var/tmp/obj/item/remote_scene_tool/linked
	icon = 'code/modules/maint_recycler/icons/goodies/remote_scene_tools.dmi'
	icon_override = 'code/modules/maint_recycler/icons/goodies/remote_scene_tools.dmi'
	item_state = "InvalidState" //so it defaults to the empty icon
	var/icon_root = "sticker"
	icon_state = "sticker_inactive"
	name = "Bluespace Sticker"
	desc = "A stretchable, flexible sticker that induces a quasi-stable 4th dimensional bluespace buzzword rift, enabling moderate levels of touch between the two."
	slot_flags = (SLOT_OCLOTHING | SLOT_ICLOTHING | SLOT_GLOVES | SLOT_MASK | SLOT_HEAD | SLOT_FEET | SLOT_ID | SLOT_BELT | SLOT_BACK | SLOT_POCKET)
	w_class = ITEMSIZE_SMALL
	var/tmp/mob/worn_mob
	/// The wearer of the partner tool, kept for the look: set when either end moves, logs in or out (linked_updated()). A reference, cleared when that mob is deleted.
	var/tmp/mob/partner_wearer
	/// The partner wearer's name when it was last looked at (linked_updated()): the doll is named after it.
	var/partner_name
	/// Whether the partner is a live one (sanity_check()): the tool shows its lit state while it is.
	var/partner_live = FALSE
	var/last_loc
	var/can_summon = TRUE
	var/can_replace = TRUE

	var/replacementType = /obj/item/remote_scene_tool

/obj/item/remote_scene_tool/proc/link_to(obj/item/remote_scene_tool/to_link)
	//link to a remote scene tool
	if(linked())
		return

	rel_set(src, nameof(linked), to_link)
	// rel_one(back =): the partner now names us back.
	linked_updated()
	to_link?.linked_updated()

/obj/item/remote_scene_tool/proc/register_to_mob(mob)
	if(worn_mob() == mob)
		return

	if(worn_mob())
		unregister_from_mob(worn_mob())

	rel_set(src, nameof(worn_mob), mob)

	observe(mob, /datum/notice/mob_login, src, then(PROC_REF(worn_mob_logged_in)))
	observe(mob, /datum/notice/mob_logout, src, then(PROC_REF(worn_mob_logged_out)))
	transmit_emote(src, span_notice("\The [src] has been put on by [mob]!"))

/obj/item/remote_scene_tool/proc/unregister_from_mob(mob)
	if(worn_mob() == null) return
	unobserve(worn_mob(), /datum/notice/mob_login, src)
	unobserve(worn_mob(), /datum/notice/mob_logout, src)
	rel_clear(src, nameof(worn_mob))
	transmit_emote(src, span_warning("\The [src]'s wearer has removed it!"))

//called when the mob wearing this item logs out
/obj/item/remote_scene_tool/proc/worn_mob_logged_out(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	if(!linked())
		return
	transmit_emote(src, span_warning("\The [src]'s wearer has gone SSD!"))
	linked()?.linked_updated()

/obj/item/remote_scene_tool/proc/worn_mob_logged_in(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	//called when the mob wearing this item logs in
	if(!linked())
		return
	transmit_emote(src, "\The [src]'s wearer has returned from SSD!")
	linked()?.linked_updated()

/obj/item/remote_scene_tool/see_emote(mob/M as mob, text, emote_type)
	if(M == getWearer())
		//we're the one doing the emote
		transmit_emote(src, text,emote_type)

/obj/item/remote_scene_tool/proc/transmit_emote(mob/M as mob, text, emote_type)
	if(linked() == null) return
	if(ismob(linked().getWearer()))
		var/mob/m = linked().getWearer()
		if(!m.client) return;
		to_chat(linked().loc, icon2html(src,m.client) + text)

	//transmit the emote to the other side

/obj/item/remote_scene_tool/proc/sanity_check()
	//check if the other side is still valid
	. = TRUE
	if(!linked())
		return FALSE
	if(linked().linked() != src)
		return FALSE

	var/mob/m = linked().getWearer()
	if(!ismob(m))
		return FALSE
	if(!m.client) //no scene partner? whoopsie!
		return FALSE

/obj/item/remote_scene_tool/Initialize(mapload)
	. = ..()
	observe(src, /datum/notice/atom_entering, src, then(PROC_REF(check_loc)))

/obj/item/remote_scene_tool/proc/check_loc(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	after(src, 0.1 SECONDS, PROC_REF(delayed_loc_check))

/obj/item/remote_scene_tool/proc/delayed_loc_check()
//why is this delayed? because when moving stuff between slots, it considers it in a different spot, and calls the commsig multiple times - so the end
//user just gets the shit spammed out of them
	if(last_loc == loc)
		return
	last_loc = loc
	linked()?.linked_updated()
	linked_updated()

	var/mob/m = getWearer()

	if(ismob(m))
		register_to_mob(m) //handles any caching
	else
		if(worn_mob())
			unregister_from_mob(worn_mob()) //unregister from the mob if we aren't on it anymore

/// The partner or its wearer changed (moved, logged in or out, linked): the state the look shows is written through its setters, and the draw follows.
/obj/item/remote_scene_tool/proc/linked_updated()
	set_partner_live(sanity_check() ? TRUE : FALSE)
	var/obj/item/remote_scene_tool/partner = linked()
	var/mob/wearer = partner?.getWearer()
	if(wearer != partner_wearer)
		rel_set(src, nameof(partner_wearer), wearer)
	set_partner_name(wearer?.name)

TRACKED(/obj/item/remote_scene_tool, partner_live)
TRACKED(/obj/item/remote_scene_tool, partner_name)

/obj/item/remote_scene_tool/draw(datum/look/look)
	..()
	look.state(partner_live ? icon_root : "[icon_root]_inactive")

// its linked tool forgets it; its wearer is unregistered.
/obj/item/remote_scene_tool/on_destroy(force)
	..()
	unregister_from_mob(worn_mob())

/obj/item/remote_scene_tool/examine(mob/user)
	. = ..()
	if(!linked())
		. += span_warning("This is not linked to anything!")
		return

	var/mob/living/carbon/human/lw = linked().getWearer()
	if(lw)
		. += span_notice("This is linked to [lw]'s [linked().name].")
		if(!lw.client || lw.stat == UNCONSCIOUS || lw.stat == DEAD)
			. += span_warning("The wearer of \the [src]'s counterpart doesn't appear to be conscious!")
	else
		. += span_notice("Its counterpart seems to be in \the [get_area(linked()).name]")

	if(!ismob(linked().loc))
		. += span_warning("\The [src]'s counterpart isn't being worn or carried by anyone!")

/obj/item/storage/box/remote_scene_tools
	icon = 'code/modules/maint_recycler/icons/goodies/remote_scene_tools.dmi'
	icon_state = "stickerbox"
	name = "box of bluespace stickers"
	desc = "A box containing a few bluespace stickers. Moderately obsolete, limited range dimensional bypass technology that enables remote \"things\" and \"stuff\" as if there were no distance at all between them!"
	var/primary = /obj/item/remote_scene_tool
	var/secondary = /obj/item/remote_scene_tool
	description_fluff = "A long since discarded prototype of a bag of holding - turns out it's hard to store things securely when the other end's open. too bad NOBODY has EVER found a practical use for them!"

/obj/item/storage/box/remote_scene_tools/Initialize(mapload)
	. = ..()
	//set the contents to be a few remote scene tools
	var/obj/item/remote_scene_tool/RST = new primary(loc = src)
	var/obj/item/remote_scene_tool/RST2 = new secondary(loc = src)
	RST.link_to(RST2)
	RST2.link_to(RST)
	calibrate_size()

/obj/item/remote_scene_tool/proc/getWearer()
	if(ismob(loc))
		return loc
	if(istype(loc,/obj/item/clothing))
		if(ismob(loc.loc))
			return loc.loc
	return null

CAPABILITIES(/obj/item/remote_scene_tool)
	links(/obj/item/remote_scene_tool::linked, /obj/item/remote_scene_tool::linked)
	ref_one(nameof(worn_mob), /mob)
	ref_one(nameof(partner_wearer), /mob)
	op("remote_scene_tool_verb_summon", menu(), label("Summon Counterpart"), needs(carried()), then(PROC_REF(remote_scene_tool_verb_summon)))

/// Old Summon Counterpart verb: Forcibly moves the linked object over to you - or, if it doesn't exist, spawn a new one.
/obj/item/remote_scene_tool/proc/remote_scene_tool_verb_summon(datum/act/op/A)
	var/mob/user = A.actor
	if(can_summon || (linked() == null && can_replace))
		if(linked() == null)
			create_counterpart()
			to_chat(user,span_notice("\The [src] forms a new [linked()]!"))
		else
			var/mob/counterpart = linked().getWearer()
			if(counterpart)
				counterpart.remove_from_mob(linked(),get_turf(src))
			else
				linked().forceMove(get_turf(src))
			to_chat(user,span_notice("\The [linked()] materializes in front of you!"))
	else
		to_chat(user,span_notice("Nothing seems to happen!"))

/obj/item/remote_scene_tool/proc/create_counterpart()
	var/obj/item/remote_scene_tool/newrst = new replacementType(get_turf(src))
	link_to(newrst)
	newrst.link_to(src)

/// Accessor for the linked var.
/obj/item/remote_scene_tool/proc/linked() as /obj/item/remote_scene_tool
	return linked

/// Accessor for the worn_mob var.
/obj/item/remote_scene_tool/proc/worn_mob() as /mob
	return worn_mob
