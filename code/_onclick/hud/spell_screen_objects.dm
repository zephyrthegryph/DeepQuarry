/atom/movable/screen/movable/spell_master
	name = "Spells"
	icon = 'icons/mob/screen_spells.dmi'
	icon_state = "wiz_spell_ready"
	// Our spell buttons are the spell_button_on relation: spell_buttons().
	var/showing = 0

	var/open_state = "master_open"
	var/closed_state = "master_closed"

	screen_loc = ui_spell_master

	/// The mob whose spells these are (a relation view; the mob owns us in spell_masters).
	var/mob/spell_holder

/// A spell button -> the spell master it is listed on. The master reads its buttons with
/// spell_buttons(), a button its master with spell_master_of(). Either end going drops the edge;
/// an emptied master deletes itself when next clicked.
/datum/om/relation/spell_button_on
	name = "spell button"
	source_single = TRUE

// the mob owns us in its spell_masters list; we leave it in phase 2.
// (Screen objects leave every client's screen in phase 5.)

/// The mob whose spells these are (a relation view: null once that is deleted).
/atom/movable/screen/movable/spell_master/proc/spell_holder() as /mob
	return spell_holder

/atom/movable/screen/movable/spell_master/MouseDrop()
	if(showing)
		return

	return ..()

/atom/movable/screen/movable/spell_master/Click()
	if(!length(spell_buttons()))
		spent(src)
		return

	toggle_open()

/atom/movable/screen/movable/spell_master/proc/toggle_open(forced_state = 0)
	if(showing && (forced_state != 2))
		var/mob/spell_holder = spell_holder()
		for(var/atom/movable/screen/spell/O as anything in spell_buttons())
			if(spell_holder && spell_holder.client)
				spell_holder.client.screen -= O
			O.handle_icon_updates = 0
		showing = 0
		overlays.len = 0
		overlays.Add(closed_state)
	else if(forced_state != 1)
		open_spellmaster()
		update_spells(1)
		showing = 1
		overlays.len = 0
		overlays.Add(open_state)

/atom/movable/screen/movable/spell_master/proc/open_spellmaster()
	var/list/screen_loc_xy = splittext(screen_loc,",")

	//Create list of X offsets
	var/list/screen_loc_X = splittext(screen_loc_xy[1],":")
	var/x_position = decode_screen_X(screen_loc_X[1])
	var/x_pix = screen_loc_X[2]

	//Create list of Y offsets
	var/list/screen_loc_Y = splittext(screen_loc_xy[2],":")
	var/y_position = decode_screen_Y(screen_loc_Y[1])
	var/y_pix = screen_loc_Y[2]

	var/mob/spell_holder = spell_holder()
	var/list/spell_objects = spell_buttons()
	for(var/i = 1; i <= length(spell_objects); i++)
		var/atom/movable/screen/spell/S = spell_objects[i]
		var/xpos = x_position + (x_position < 8 ? 1 : -1)*(i%7)
		var/ypos = y_position + (y_position < 8 ? round(i/7) : -round(i/7))
		if(spell_holder && spell_holder.client)
			S.screen_loc = "[encode_screen_X(xpos)]:[x_pix],[encode_screen_Y(ypos)]:[y_pix]"
			spell_holder.client.screen += S
			S.handle_icon_updates = 1

/atom/movable/screen/movable/spell_master/proc/add_spell(datum/spell/spell)
	if(!spell) return

	var/mob/spell_holder = spell_holder()
	if(spell.connected_button) //we have one already, for some reason
		if(spell.connected_button.spell_master_of() == src)
			return
		else
			om_link(spell.connected_button, src, /datum/om/relation/spell_button_on)
			if(spell_holder?.client)
				toggle_open(2)
			return

	if(spell.spell_flags & NO_BUTTON) //no button to add if we don't get one
		return

	var/atom/movable/screen/spell/newscreen = new /atom/movable/screen/spell()
	rel_set(newscreen, nameof(newscreen.spell), spell)

	rel_set(spell, nameof(spell.connected_button), newscreen)

	if(!spell.override_base) //if it's not set, we do basic checks
		if(spell.spell_flags & CONSTRUCT_CHECK)
			newscreen.spell_base = "const" //construct spells
		else
			newscreen.spell_base = "wiz" //wizard spells
	else
		newscreen.spell_base = spell.override_base
	newscreen.name = spell.name
	om_link(newscreen, src, /datum/om/relation/spell_button_on)
	newscreen.update_charge(1)
	if(spell_holder?.client)
		toggle_open(2) //forces the icons to refresh on screen

/atom/movable/screen/movable/spell_master/proc/remove_spell(datum/spell/spell)
	own_clear(spell, nameof(spell.connected_button), OWN_DELETE)

	if(length(spell_buttons()))
		toggle_open(showing + 1)
	else
		spent(src)

/atom/movable/screen/movable/spell_master/proc/silence_spells(amount)
	for(var/atom/movable/screen/spell/spell as anything in spell_buttons())
		var/datum/spell/its_spell = spell.spell()
		if(its_spell)
			its_spell.silenced = amount
		spell.update_charge(1)

/atom/movable/screen/movable/spell_master/proc/update_spells(forced = 0, mob/user)
	if(user && user.client)
		if(!(src in user.client.screen))
			user.client.screen += src
	for(var/atom/movable/screen/spell/spell as anything in spell_buttons())
		spell.update_charge(forced)

/atom/movable/screen/movable/spell_master/genetic
	name = "Mutant Powers"
	icon_state = "genetic_spell_ready"

	open_state = "genetics_open"
	closed_state = "genetics_closed"

	screen_loc = ui_genetic_master

/atom/movable/screen/movable/spell_master/swarm
	name = "Swarm Abilities"
	icon_state = "nano_spell_ready"

	open_state = "swarm_open"
	closed_state = "swarm_closed"

//////////////ACTUAL SPELLS//////////////
//This is what you click to cast things//
/////////////////////////////////////////
/atom/movable/screen/spell
	icon = 'icons/mob/screen_spells.dmi'
	icon_state = "wiz_spell_base"
	var/spell_base = "wiz"
	var/last_charge = 0 //not a time, but the last remembered charge value

	/// OM handle of the spell this button casts; read with spell().
	var/datum/spell/spell
	var/handle_icon_updates = 0
	// The master we are listed on is the spell_button_on relation: spell_master_of().

	var/icon/last_charged_icon


/// The spell this button casts (a relation view: null once that is deleted).
/atom/movable/screen/spell/proc/spell() as /datum/spell
	return spell

/atom/movable/screen/spell/proc/update_charge(forced_update = 0)
	var/datum/spell/spell = spell()
	if(!spell)
		ended_with(src)
		return

	if((last_charge == spell.charge_counter || !handle_icon_updates) && !forced_update)
		return //nothing to see here

	cut_overlay(spell.hud_state)

	if(spell.charge_type == Sp_RECHARGE || spell.charge_type == Sp_CHARGES)
		if(spell.charge_counter < spell.charge_max)
			icon_state = "[spell_base]_spell_base"
			if(spell.charge_counter > 0)
				var/icon/partial_charge = icon(src.icon, "[spell_base]_spell_ready")
				partial_charge.Crop(1, 1, partial_charge.Width(), round(partial_charge.Height() * spell.charge_counter / spell.charge_max))
				overlays += partial_charge
				if(last_charged_icon)
					cut_overlay(last_charged_icon)
				last_charged_icon = partial_charge
			else if(last_charged_icon)
				cut_overlay(last_charged_icon)
				last_charged_icon = null
		else
			icon_state = "[spell_base]_spell_ready"
			if(last_charged_icon)
				cut_overlay(last_charged_icon)
	else
		icon_state = "[spell_base]_spell_ready"

	add_overlay(spell.hud_state)

	last_charge = spell.charge_counter

	cut_overlay("silence")
	if(spell.silenced)
		overlays += "silence"

CAPABILITIES(/atom/movable/screen/spell)
	click_on(PROC_REF(click_input))

/// The native Click's actor and arguments, handed over by the engine (click_on(), code/engine/lifeforms/input.dm).
/atom/movable/screen/spell/proc/click_input(datum/act/input/A)
	return cast_with_actor(A.actor)

/atom/movable/screen/spell/proc/cast_with_actor(mob/user)
	var/datum/spell/spell = spell()
	if(!user || !spell)
		spent(src, user)
		return

	spell.perform(user)
	update_charge(1)
