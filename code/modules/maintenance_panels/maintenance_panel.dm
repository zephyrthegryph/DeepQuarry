/obj/structure/window/maintenance_panel
	name = "maintenance panel"
	desc = "A maintenance panel. It covers important things hidden inside the wall."
	icon = 'icons/obj/maintenance_panel.dmi'
	icon_state = "panel"
	basestate = "panel"
	max_integrity = 350
	glasstype = /obj/item/stack/tile/maintenance_panel // Yes these are technically windows, drops into their panel on deconstruct and shatter
	maximal_heat = /datum/material/steel::melting_point
	force_threshold = 5
	shardtype = null
	opacity = 1 // Difficult to see past

/obj/structure/window/maintenance_panel/apply_silicate(amount)
	return // can't fix it like that

/obj/structure/window/maintenance_panel/is_fulltile()
	return FALSE // NEVER

CAPABILITIES(/obj/structure/window/maintenance_panel)
	op("maintenance_panel_interaction_item", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), then(PROC_REF(maintenance_panel_interaction_item)))
	op("weld_toggle", tool(TOOL_WELDER), stance(I_DISARM, I_GRAB, I_HURT), label("Weld or cut"), priority(OP_PRIORITY_PART + 10), wait(2 SECONDS), costs(RES_FUEL, 1), needs(req_welder_lit()), begins(PROC_REF(weld_begins)), starts(PROC_REF(weld_started)), then(PROC_REF(weld_toggle_done)))
	op("weld_toggle_help", tool(TOOL_WELDER), stance(I_HELP), when(cond_not(PROC_REF(is_damaged))), label("Weld or cut"), priority(OP_PRIORITY_TAKE_OUT), wait(2 SECONDS), costs(RES_FUEL, 1), needs(req_welder_lit()), begins(PROC_REF(weld_begins)), starts(PROC_REF(weld_started)), then(PROC_REF(weld_toggle_done)))
	op("swallow", observer(), label("Nothing"), then(TYPE_PROC_REF(/atom, op_swallow)))

/// Old attackby.
/obj/structure/window/maintenance_panel/proc/maintenance_panel_interaction_item(datum/act/op/A)
	if(istype(A.held, /obj/item/stack/cable_coil))
		return OP_PASS
	return OP_DECLINE

/obj/structure/window/maintenance_panel/screwdriver_act(mob/user, obj/item/tool)
	return ITEM_INTERACT_BLOCKING

/obj/structure/window/maintenance_panel/proc/weld_begins(datum/act/op/A)
	return msg_text(span_warning("You begin to [!anchored ? "weld" : "cut"] the [src] [!anchored ? "to" : "off"] the wall."))

/obj/structure/window/maintenance_panel/proc/weld_started(datum/act/op/A)
	var/obj/item/tool = A.held
	playsound(src, tool.usesound, 75, 1)

/obj/structure/window/maintenance_panel/proc/weld_toggle_done(datum/act/op/A)
	set_anchored(!anchored)
	update_nearby_tiles(need_rebuild = 1)
	update_verbs()
	to_chat(A.actor, span_info("You [anchored ? "weld" : "cut"] the [src] [anchored ? "to" : "off"] the wall."))
	return OP_OK


// Heavier panel takes a metal-scrape sound on big hits, glass tink on small ones.
/obj/structure/window/maintenance_panel/play_attack_sound(damage_amount, damage_type, damage_flag)
	if(damage_amount < 30)
		play_sfx(src, SFX_EFFECTS_GLASSHIT, volume = 100)
	else
		play_sfx(src, SFX_EFFECTS_GRILLEHIT, 1.5)

/obj/structure/window/maintenance_panel/shatter(display_message = 1)
	play_sfx(src, SFX_EFFECTS_METALSCRAPE)
	if(display_message)
		visible_message("\the [src] thunks free of the wall!")
	replace_with(src, glasstype)


/obj/structure/window/maintenance_panel/examine(mob/user)
	. = ..()
	if(anchored)
		. += span_notice("It's welded firmly in place.")
	else
		. += span_warning("It's hanging freely, and hasn't been welded in place! It can be deconstructed with a wrench.")
