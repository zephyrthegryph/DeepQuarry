// The lighting system
//
// consists of light fixtures (/obj/machinery/light) and light tube/bulb items (/obj/item/light)

// status values shared between lighting fixtures and items
#define LIGHT_BULB_TEMPERATURE 400 //K - used value for a 60W bulb
#define LIGHTING_POWER_FACTOR 2		//2W per luminosity * range
#define LIGHT_EMERGENCY_POWER_USE 0.2 //How much power emergency lights will consume per tick

DECLARE_SHARED_CACHE(light_type_instance, GLOBAL_PROC_REF(build_light_type_instance), SC_NEVER)

/proc/build_light_type_instance(light_type)
	return new light_type

/proc/get_light_type_instance(light_type)
	return CACHED(light_type_instance, light_type)

// the standard tube light fixture
//
// The fixture is declared (doc/rewrite/final_api.html section 16, doc/rewrite/conversion_guide.md): ONE CAPABILITIES list says what it is: a machine
// on the area's light channel, the bulb in its socket and the emergency cell it holds, the area it stands in, the ops that put a bulb in, take one
// out, smash, open and tune it, the night shift and emergency switches it reads from its area, the timers of its cell and its flicker. The
// imperative parts below are its own: the light arithmetic of refresh_light(), the emergency discharge accounting, the conditions and effects the
// list names and its look.
//
// What the machine core keeps until the machine track (phase 4): the NOPOWER bit, power_change() (the area calls it on every channel change and
// on every use of a light switch: the fixture reads has_power() then), `on`, set_use_power() and the update of the area's power tally.

STAT(/obj/machinery/light, nightshift_enabled, ANY)
STAT(/obj/machinery/light, area_emergency_off, ANY)

MSG_DEF_SELF(light/fitted, "There is a bulb in it already.")
MSG_DEF_SELF(light/wrong_kind, "This type of light requires another kind.")

/obj/machinery/light
	name = "light fixture"
	icon = 'icons/obj/lighting.dmi'
	var/base_state = "tube"		// base description and icon_state
	icon_state = "tube1"
	desc = "A lighting fixture."
	anchored = TRUE
	plane = MOB_PLANE
	layer = BELOW_MOB_LAYER
	use_power = USE_POWER_ACTIVE
	idle_power_usage = 2
	active_power_usage = 10
	power_channel = LIGHT
	max_integrity = 20
	integrity_failure = 0.5
	/// What light is currently in the socket. Use bulb() to read it.
	var/obj/item/light/installed_light
	/// A pristine light_type bulb held as data (C5): its status, switchcount and rigged are the fixture's own. bulb() makes it real.
	var/latent_bulb = FALSE
	/// Charge of a pristine emergency cell held as data (C5), or null for none. emergency_cell() makes it real.
	var/latent_cell_charge = null
	on = 0					// 1 if on, 0 if off
	var/brightness_range
	var/brightness_power
	var/brightness_color
	/// LIGHT_OK, _EMPTY, _BURNED or _BROKEN.
	var/status = LIGHT_OK
	/// flicker(): flicks still to go, the flicker colour, and the colours to restore at the end.
	var/tmp/flicks_left = 0
	var/tmp/flicker_color
	var/tmp/flicker_original_color
	var/tmp/flicker_original_color_ns
	var/light_type = /obj/item/light/tube		// the type of light item
	var/construct_type = /obj/machinery/light_construct
	/// How many times it was switched on: the odds of the bulb burning out.
	var/switchcount = 0
	var/rigged = 0				// true if rigged to explode
	var/needsound = FALSE		// Flag to prevent playing turn-on sound multiple times, and from playing at roundstart
	var/shows_alerts = TRUE		// Flag for if this fixture should show alerts.  Make sure icon states exist!
	var/current_alert = null	// Which alert are we showing right now?
	var/auto_flicker = FALSE // If true, will constantly flicker, so long as someone is around to see it (otherwise its a waste of CPU).
	var/obj/item/cell/emergency_light/cell
	/// World time the emergency discharge was last settled (0 for none).
	EXPIRY_DECLARE(emergency_discharge_started)
	var/start_with_cell = TRUE	// if true, this fixture generates a very weak cell at roundstart
	var/emergency_mode = FALSE	// if true, the light is in emergency mode
	var/no_emergency = FALSE	// if true, this light cannot ever have an emergency mode
	var/bulb_emergency_brightness_mul = 0.25	// multiplier for this light's base brightness in emergency power mode
	var/bulb_emergency_colour = "#FF3232"	// determines the colour of the light while it's in emergency mode
	var/bulb_emergency_pow_mul = 0.75	// the multiplier for determining the light's power in emergency mode
	var/bulb_emergency_pow_min = 0.5	// the minimum value for the light's power in emergency mode
	var/nightshift_allowed = TRUE
	var/brightness_range_ns
	var/brightness_power_ns
	var/brightness_color_ns
	var/overlay_color = LIGHT_COLOR_INCANDESCENT_TUBE
	var/flickering = FALSE
	var/overlay_above_everything = TRUE
	/// The area's lights power state the fixture last acted on (so a channel change that changes nothing here does nothing).
	var/tmp/last_area_power = null

TRACKED(/obj/machinery/light, status)
TRACKED(/obj/machinery/light, current_alert)
TRACKED(/obj/machinery/light, overlay_color)
TRACKED(/obj/machinery/light, emergency_mode)
TRACKED(/obj/machinery/light, nightshift_allowed)
TRACKED(/obj/machinery/light, flickering)
TRACKED(/obj/machinery/light, auto_flicker)

CAPABILITIES(/obj/machinery/light)
	extend(/datum/act/hit/generic, instead(then(PROC_REF(smashed_by))))
	powered(POWER_CHANNEL_LIGHTING)
	owns_one(nameof(installed_light), /obj/item/light)
	owns_one(nameof(cell), /obj/item/cell/emergency_light)
	contributes(STAT_NIGHTSHIFT_ENABLED, PROC_REF(wants_nightshift))
	contributes(STAT_AREA_EMERGENCY_OFF, PROC_REF(emergency_switched_off))
	op("insert", item(/obj/item/light), label("Insert bulb"), wait(0),
		needs(req(PROC_REF(can_take_bulb), because = PROC_REF(bulb_refusal))), then(PROC_REF(insert_held)))
	op("remove", hand(), when(req_empty_hand()), label("Remove bulb"), wait(0), then(PROC_REF(take_bulb)))
	op("hit", item(/obj/item), hostile(), wait(0), then(PROC_REF(hit_by)))
	op("toggle_emergency", remote(), label("Toggle emergency lights"), wait(0), then(PROC_REF(toggle_emergency_lights)))
	op("remote_flicker", remote(), gesture(GESTURE_ALT), when(req(/mob/living/silicon/ai, of = ON_ACTOR)), label("Flicker"), wait(0),
		then(PROC_REF(remote_flicker)))
	op("open_casing", tool(TOOL_SCREWDRIVER), when(PROC_REF(socket_empty)), wait(0), then(PROC_REF(open_casing)))
	op("tune", tool(TOOL_MULTITOOL), when(PROC_REF(bulb_can_be_tuned)), light_tune_parts(TYPE_PROC_REF(/obj/machinery/light, tune_needs_number), TYPE_PROC_REF(/obj/machinery/light, tune_needs_color)), then(PROC_REF(tuned)))
	examine_line(PROC_REF(examine_status))
	examine_line(PROC_REF(examine_charge))
	on_change(nameof(status), ANY, then(PROC_REF(status_changed)))
	on_change(nameof(nightshift_enabled), ANY, then(PROC_REF(area_lighting_changed)))
	on_change(nameof(area_emergency_off), ANY, then(PROC_REF(area_lighting_changed)))
	every(PROC_REF(flicker_delay), then(PROC_REF(do_flicker)), when = nameof(flickering))
	every(2 SECONDS, then(PROC_REF(auto_flicker_check)), when = PROC_REF(flicker_watching))
	param(nameof(construct_at_make), pos = 1, keep = FALSE)

/// The area's night shift reaches a fixture through its area (the area's stat is fed by its APC); a fixture that does not allow it ignores it.
/obj/machinery/light/proc/wants_nightshift(datum/act/A)
	return nightshift_allowed && power_area?.lights_nightshift

/// The area's APC switched emergency lighting off.
/obj/machinery/light/proc/emergency_switched_off(datum/act/A)
	return !!power_area?.lights_emergency_off

/// The area's night shift or emergency lighting changed: the fixture redraws its light.
/obj/machinery/light/proc/area_lighting_changed(datum/act/A)
	if(QDELETED(src))
		return
	refresh_light(FALSE)

/// A bulb that is not whole switches the fixture off (also for a status written by someone else, at the next drain).
/obj/machinery/light/proc/status_changed(datum/act/A)
	if(status != LIGHT_OK)
		set_on(FALSE)

/// The fixture's bulb state, and the light off at once when the bulb is not whole.
/obj/machinery/light/proc/set_bulb_status(value)
	set_status(value)
	if(status != LIGHT_OK)
		set_on(FALSE)

/obj/machinery/light/flicker
	auto_flicker = TRUE

/obj/machinery/light/no_nightshift
	nightshift_allowed = FALSE

// the smaller bulb light fixture

/obj/machinery/light/small
	icon_state = "bulb1"
	base_state = "bulb"
	desc = "A small lighting fixture."
	light_type = /obj/item/light/bulb
	construct_type = /obj/machinery/light_construct/small
	shows_alerts = FALSE
	overlay_color = LIGHT_COLOR_INCANDESCENT_BULB

/obj/machinery/light/small/flicker
	auto_flicker = TRUE

/obj/machinery/light/poi
	start_with_cell = FALSE

/obj/machinery/light/small/poi
	start_with_cell = FALSE

/obj/machinery/light/flamp
	icon = 'icons/obj/lighting.dmi'
	icon_state = "flamp1"
	base_state = "flamp"
	plane = OBJ_PLANE
	layer = OBJ_LAYER
	desc = "A floor lamp."
	light_type = /obj/item/light/bulb/large
	construct_type = /obj/machinery/light_construct/flamp
	shows_alerts = FALSE
	var/lamp_shade = 1
	overlay_color = LIGHT_COLOR_INCANDESCENT_BULB

TRACKED(/obj/machinery/light/flamp, lamp_shade)

/obj/machinery/light/flamp/flicker
	auto_flicker = TRUE

/obj/machinery/light/small/emergency
	light_type = /obj/item/light/bulb/red
	nightshift_allowed = FALSE

/obj/machinery/light/small/emergency/flicker
	auto_flicker = TRUE

/obj/machinery/light/spot
	name = "spotlight"
	light_type = /obj/item/light/tube/large
	shows_alerts = FALSE

/obj/machinery/light/spot/no_nightshift
	nightshift_allowed = FALSE

/obj/machinery/light/spot/flicker
	auto_flicker = TRUE

/obj/machinery/light/flamp/noshade
	lamp_shade = 0

// ---- what it looks like ----

/// The fixture's picture: the bulb's state, and the glow of a lit tube.
/obj/machinery/light/draw(datum/look/look)
	..()
	switch(status)
		if(LIGHT_OK)
			if(shows_alerts && current_alert && on)
				look.state("[base_state]-alert-[current_alert]")
				look.overlay(light_overlay(FALSE, "[base_state]-alert-[current_alert]"))
			else
				look.state("[base_state][on]")
				if(on)
					look.overlay(light_overlay())
		if(LIGHT_EMPTY)
			look.state("[base_state]-empty")
		if(LIGHT_BURNED)
			look.state("[base_state]-burned")
		if(LIGHT_BROKEN)
			look.state("[base_state]-broken")

/// A floor lamp with a shade is drawn in its shade; without it, as any fixture.
/obj/machinery/light/flamp/draw(datum/look/look)
	if(!lamp_shade)
		return ..()
	switch(status)
		if(LIGHT_OK)
			look.state("flampshade[on]")
			if(on)
				look.overlay(light_overlay(TRUE, null, "flampshade"))
		if(LIGHT_EMPTY, LIGHT_BURNED, LIGHT_BROKEN)
			look.state("flampshade0")

/// The lit glow over the sprite: tinted by the light's colour, above the lighting or emissive.
/obj/machinery/light/proc/light_overlay(do_color = TRUE, provided_state = null, state_base = null)
	var/image/overlay_layer
	if(provided_state)
		overlay_layer = image(icon, "[provided_state]-overlay")
	else
		overlay_layer = image(icon, "[state_base || base_state]-overlay")
	overlay_layer.appearance_flags = RESET_COLOR|KEEP_APART
	if(overlay_color && do_color)
		overlay_layer.color = overlay_color
	overlay_layer.plane = overlay_above_everything ? PLANE_LIGHTING_ABOVE : PLANE_EMISSIVE
	return overlay_layer

/// Within two tiles the fixture says what is in it.
/obj/machinery/light/proc/examine_status(datum/act/op/A)
	var/fitting = get_fitting_name()
	switch(status)
		if(LIGHT_OK)
			return "It is turned [on ? "on" : "off"]."
		if(LIGHT_EMPTY)
			return "The [fitting] has been removed."
		if(LIGHT_BURNED)
			return "The [fitting] is burnt out."
		if(LIGHT_BROKEN)
			return "The [fitting] has been smashed."
	return null

/// What the emergency cell holds, counting the drain that has not been settled yet.
/obj/machinery/light/proc/examine_charge(datum/act/op/A)
	if(!has_cell())
		return null
	var/charge = cell ? cell.charge : latent_cell_charge
	var/maxcharge = cell ? cell.maxcharge : initial(/obj/item/cell/emergency_light::maxcharge)
	if(cell && emergency_discharge_started)
		charge = max(0, charge - LIGHT_EMERGENCY_POWER_USE * (max(0, EXPIRY_NOW(src, CLOCK_WORLD) - emergency_discharge_started) / (2 SECONDS)))
	return "Its backup power charge meter reads [round((charge / maxcharge) * 100, 0.1)]%."

// ---- alerts ----

/obj/machinery/light/proc/set_alert_atmos()
	if(!shows_alerts)
		return
	set_current_alert("atmos")
	light_color = "#6D6DFC"
	brightness_color = "#6D6DFC"
	refresh_light()

/obj/machinery/light/proc/set_alert_fire()
	if(!shows_alerts)
		return
	set_current_alert("fire")
	light_color = "#FF3030"
	brightness_color = "#FF3030"
	refresh_light()

/obj/machinery/light/proc/reset_alert()
	if(!shows_alerts)
		return

	set_current_alert(null)
	var/obj/item/light/L = bulb() //This ensures any special bulbs will stay special!

	if(L)
		update_from_bulb(L)
	else
		brightness_color = nightshift_enabled ? initial(brightness_color_ns) : initial(brightness_color)

	refresh_light()

/obj/machinery/light/proc/set_alert_engineering()
	if(!shows_alerts)
		return
	set_current_alert("eng")
	light_color = "#ff9900"
	brightness_color = "#ff9900"
	refresh_light()

// ---- the light the fixture gives ----

/// Works out what the fixture gives now (its bulb, the night shift, an alert, its cell) and sets it. `trigger`: a change of light may burn the bulb
/// out or set off a rigged one (the callers that merely follow an area or a flicker pass FALSE).
/obj/machinery/light/proc/refresh_light(trigger = 1)
	if(!on)
		needsound = TRUE // Play sound next time we turn on
	else if(needsound)
		play_sfx(src, SFX_EFFECTS_LIGHTON)
		needsound = FALSE // Don't play sound again until we've been turned off

	if(on)
		var/correct_range = nightshift_enabled ? brightness_range_ns : brightness_range
		var/correct_power = nightshift_enabled ? brightness_power_ns : brightness_power
		var/correct_color = nightshift_enabled ? brightness_color_ns : brightness_color
		var/correct_overlay = nightshift_enabled ? brightness_color_ns : brightness_color //Gives lights the correct overlay if NS is enabled.
		if(current_alert) //Oh no, we're on fire! Or the atmos is bad! Let's change the color
			correct_range = brightness_range
			correct_power = brightness_power
			correct_color = brightness_color
		if(light_range != correct_range || light_power != correct_power || light_color != correct_color || overlay_color != correct_overlay)
			if(!auto_flicker)
				switchcount++
			if(rigged)
				if(status == LIGHT_OK && trigger)

					log_admin("LOG: Rigged light explosion, last touched by [forensic_data?.get_lastprint()]")
					message_admins("LOG: Rigged light explosion, last touched by [forensic_data?.get_lastprint()]")

					explode()
			else if( prob( min(60, switchcount*switchcount*0.01) ) )
				if(status == LIGHT_OK && trigger)
					set_bulb_status(LIGHT_BURNED)
					set_on(0)
					set_light(0)
			else
				set_use_power(USE_POWER_ACTIVE)
				set_light(correct_range, correct_power, correct_color)
				set_overlay_color(correct_overlay)
		if(cell?.charge < cell?.maxcharge)
			schedule_emergency_recharge()
	else if(has_emergency_power(LIGHT_EMERGENCY_POWER_USE) && !turned_off())
		set_use_power(USE_POWER_IDLE)
		set_emergency_mode(TRUE)
		begin_emergency_discharge()
	else
		set_use_power(USE_POWER_IDLE)
		set_light(0)
	update_light()
	update_active_power_usage((light_range * light_power) * LIGHTING_POWER_FACTOR)

/// A simple mob's (or a xeno's) generic hit on it, taken over (the hit/generic action): HOOK_DECLINE lets the default generic attack land.
/obj/machinery/light/proc/smashed_by(datum/act/hit/generic/A)
	var/mob/user = A.attacker
	var/damage = A.damage
	if(!damage)
		return OP_OK
	if(status == LIGHT_EMPTY||status == LIGHT_BROKEN)
		to_chat(user, "That object is useless to you.")
		return OP_OK
	if(!(status == LIGHT_OK||status == LIGHT_BURNED))
		return OP_OK
	act_message(user, null, others = span_danger("%U% smashes the light!"))
	user.do_attack_animation(src)
	deal_damage(DAMAGE_BLUNT, max_integrity * (1 - integrity_failure) + DAMAGE_PRECISION, source = user, attacker = user)
	return OP_OK

// attempt to set the light's on/off status
// will not switch on if broken/burned/empty
/obj/machinery/light/proc/seton(s)
	set_on((s && status == LIGHT_OK))
	refresh_light()

/obj/machinery/light/get_cell()
	return emergency_cell()

/// Whether a bulb is fitted, real or latent.
/obj/machinery/light/proc/has_bulb()
	return installed_light || latent_bulb

/// The fitted bulb, made real if it was latent (C5). Null when empty.
/obj/machinery/light/proc/bulb()
	RETURN_TYPE(/obj/item/light)
	if(latent_bulb)
		latent_bulb = FALSE
		var/obj/item/light/made = new light_type(src)
		rel_set(src, nameof(installed_light), made)
		made.set_status(status)
		made.switchcount = switchcount
		made.rigged = rigged
	return installed_light

/// Whether an emergency cell is fitted, real or latent.
/obj/machinery/light/proc/has_cell()
	return cell || !isnull(latent_cell_charge)

/// The emergency cell, made real if it was latent (C5). Null when none.
/obj/machinery/light/proc/emergency_cell()
	RETURN_TYPE(/obj/item/cell/emergency_light)
	if(!isnull(latent_cell_charge))
		var/charge = latent_cell_charge
		latent_cell_charge = null
		rel_set(src, nameof(cell), new /obj/item/cell/emergency_light(src))
		cell.charge = charge
	return cell

/// A pristine emergency cell as data: what /obj/item/cell/emergency_light's Initialize() would give here (no charge in a naturally depowered area).
/obj/machinery/light/proc/declare_emergency_cell()
	var/area/A = get_area(src)
	var/obj/item/cell/emergency_light/typed = /obj/item/cell/emergency_light
	latent_cell_charge = (!A?.lightswitch || !A?.light_power) ? 0 : initial(typed.charge)

/obj/machinery/light/proc/get_fitting_name()
	var/obj/item/light/L = light_type
	return initial(L.name)

/obj/machinery/light/proc/update_from_bulb(obj/item/light/L)
	set_bulb_status(L.status)
	switchcount = L.switchcount
	rigged = L.rigged

	brightness_range = L.brightness_range
	brightness_power = L.brightness_power
	brightness_color = L.brightness_color
	set_overlay_color(L.brightness_color)

	brightness_range_ns = L.nightshift_range
	brightness_power_ns = L.nightshift_power
	brightness_color_ns = L.nightshift_color

// ---- the socket ----

/// Requirement: the fitting is empty and takes this kind of light.
/obj/machinery/light/proc/can_take_bulb(datum/act/op/A)
	return isnull(bulb_refusal(A))

/// Why the held light does not go in, or null.
/obj/machinery/light/proc/bulb_refusal(datum/act/op/A)
	if(status != LIGHT_EMPTY)
		return /datum/msg/light/fitted
	if(!istype(A.held, light_type))
		return /datum/msg/light/wrong_kind
	return null

/// The socket has no bulb in it.
/obj/machinery/light/proc/socket_empty(datum/act/A)
	return status == LIGHT_EMPTY

/// Puts bulb `L` in the socket, from wherever it is (`user`'s hand: told why when it can't let go).
/obj/machinery/light/proc/insert_bulb(obj/item/light/L, mob/user)
	if(user && L.loc == user && !user.unEquip(L, FALSE, src))
		return FALSE
	if(L.loc != src)
		L.forceMove(src)
	rel_set(src, nameof(installed_light), L)
	. = TRUE
	update_from_bulb(L)
	latent_bulb = FALSE

	set_on(powered() && !turned_off()) // Do not instantly turn on lights if the area lightswitch is off
	refresh_light()

	if(on && rigged)

		log_admin("LOG: Rigged light explosion, last touched by [forensic_data?.get_lastprint()]")
		message_admins("LOG: Rigged light explosion, last touched by [forensic_data?.get_lastprint()]")

		explode()

/obj/machinery/light/proc/remove_bulb()
	switchcount = 0
	rel_take(src, nameof(installed_light))
	latent_bulb = FALSE
	set_bulb_status(LIGHT_EMPTY)
	refresh_light()

/// The op's work: the held light goes in.
/obj/machinery/light/proc/insert_held(datum/act/op/A)
	var/mob/user = A.actor
	if(!insert_bulb(A.held, user))
		return OP_REFUSED
	to_chat(user, "You insert [installed_light].")
	refresh_light() // Like other places, this is done later down the line but this is essential to updating the overlay when nightmode is involved.
	add_fingerprint(user)
	return OP_OK

/// Any other item: smash the light, or stick it into an empty socket.
/obj/machinery/light/proc/hit_by(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(status != LIGHT_BROKEN && status != LIGHT_EMPTY)
		if(prob(1+W.force * 5))

			to_chat(user, "You hit the light, and it smashes!")
			for(var/mob/M in viewers(src))
				if(M == user)
					continue
				M.show_message("[user.name] smashed the light!", 3, "You hear a tinkle of breaking glass", 2)
			if(on && !(W.flags & NOCONDUCT))
				if (prob(12))
					electrocute_mob(user, get_area(src), src, 0.3)
			broken()

		else
			to_chat(user, "You hit the light!")

	// attempt to stick weapon into light socket
	else if(status == LIGHT_EMPTY)
		to_chat(user, "You stick \the [W] into the light socket!")
		if(has_power() && !(W.flags & NOCONDUCT))
			fx_sparks(src, 3)
			if (prob(75))
				electrocute_mob(user, get_area(src), src, rand(0.7,1.0))
	return OP_OK

/// A screwdriver opens an empty fixture into a wired frame of its kind, facing the way it did.
/obj/machinery/light/proc/open_casing(datum/act/op/A)
	var/mob/user = A.actor
	playsound(src, A.held.usesound, 75, TRUE)
	act_message(user, src, MSG_SELF("You open %T%'s casing."), MSG_OTHERS("[user.name] opens %T%'s casing."), MSG_BLIND("You hear a noise."))
	replace_with(src, construct_type, null, FALSE, null, src)
	return OP_OK

/// Old attack_hand: remove the tube/bulb; burns hands if not protected and the light is on. Telekinesis takes it at range.
/obj/machinery/light/proc/take_bulb(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)

	if(status == LIGHT_EMPTY)
		to_chat(user, "There is no [get_fitting_name()] in this light.")
		return OP_OK

	if(!user.Adjacent(src))
		return take_bulb_telekinetically(user)

	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		if(H.species.can_shred(H, FALSE, 10))
			user.setClickCooldown(user.get_attack_speed())
			for(var/mob/M in viewers(src))
				M.show_message(span_red("[user.name] smashed the light!"), 3, "You hear a tinkle of breaking glass", 2)
			broken()
			return OP_OK

	// a lit bulb is too hot to take out bare-handed (fire-insulated gloves, a heat-proof species, cold resistance or telekinesis do)
	if(on)
		var/prot = 0
		var/mob/living/carbon/human/H = user

		if(istype(H))
			if(H.species.heat_level_1 > LIGHT_BULB_TEMPERATURE)
				prot = 1
			else if(H.get_equipped_item(SLOT_ID_GLOVES))
				var/obj/item/clothing/gloves/G = H.get_equipped_item(SLOT_ID_GLOVES)
				if(G.max_heat_protection_temperature)
					if(G.max_heat_protection_temperature > LIGHT_BULB_TEMPERATURE)
						prot = 1
		else
			prot = 1

		if(prot > 0 || (user.has_mutation(COLD_RESISTANCE)))
			to_chat(user, "You remove the light [get_fitting_name()]")
		else if(user.has_mutation(TK))
			to_chat(user, "You telekinetically remove the light [get_fitting_name()].")
		else
			to_chat(user, "You try to remove the [get_fitting_name()], but it's too hot and you don't want to burn your hand.")
			return OP_OK // if burned, don't remove the light
	else
		to_chat(user, "You remove the light [get_fitting_name()].")

	//Let's actually put the real bulb in their hand.
	var/obj/item/light/B = bulb()
	B.set_status(status) //Update the bulb they're being given. If it's broken, the bulb should be as well!
	remove_bulb()
	user.put_in_active_hand(B)	//puts it in our active hand
	return OP_OK

/// Pull the bulb out at range into a telekinetic grab.
/obj/machinery/light/proc/take_bulb_telekinetically(mob/user)
	to_chat(user, "You telekinetically remove the light [get_fitting_name()].")
	var/obj/item/light/B = bulb()
	B.set_status(status)
	remove_bulb()
	B.forceMove(src.loc)
	var/obj/item/tk_grab/O = new(src)
	user.put_in_active_hand(O)
	rel_set(O, nameof(O.host), user)
	O.focus_object(B)
	return OP_OK

/// A silicon's touch (an AI's click through its cameras, a cyborg's): its emergency lighting goes off or on.
/obj/machinery/light/proc/toggle_emergency_lights(datum/act/op/A)
	no_emergency = !no_emergency
	to_chat(A.actor, span_notice("Emergency lights for this fixture have been [no_emergency ? "disabled" : "enabled"]."))
	refresh_light(FALSE)
	return OP_OK

// ---- the area's power ----

/// returns if the light has power /but/ is manually turned off
/// if a light is turned off, it won't activate emergency power
/obj/machinery/light/proc/turned_off()
	var/area/A = get_area(src)
	return !A.lightswitch && A.power_light || flickering

/// returns whether this light has power: true if area has power and lightswitch is on
/obj/machinery/light/proc/has_power()
	var/area/A = get_area(src)
	return A && A.lightswitch && (!A.requires_power || A.power_light)

/obj/machinery/light/flamp/has_power()
	var/area/A = get_area(src)
	if(lamp_shade)
		return A && (!A.requires_power || A.power_light)
	else
		return A && A.lightswitch && (!A.requires_power || A.power_light)

/// returns whether this light has emergency power
/// can also return if it has access to a certain amount of that power
/obj/machinery/light/proc/has_emergency_power(pwr)
	if(no_emergency || area_emergency_off || !has_cell())
		return FALSE
	var/charge = cell ? cell.charge : latent_cell_charge
	if(pwr ? charge >= pwr : charge)
		return status == LIGHT_OK

/// attempts to use power from the installed emergency cell, returns true if it does and false if it doesn't
/obj/machinery/light/proc/use_emergency_power(pwr = LIGHT_EMERGENCY_POWER_USE, drain_seconds = 0)
	if(turned_off())
		return FALSE
	if(!has_emergency_power(pwr))
		return FALSE
	var/obj/item/cell/C = emergency_cell()
	if(C.charge > 750) //it's meant to handle 120 W, ya doofus. Not Anymore!!
		visible_message(span_warning("[src] short-circuits from too powerful of a power cell!"))
		set_bulb_status(LIGHT_BURNED)
		if(installed_light)
			installed_light.set_status(status)
		return FALSE
	C.use(pwr, seconds = drain_seconds)
	set_light(brightness_range * bulb_emergency_brightness_mul, emergency_light_power(C), bulb_emergency_colour)
	return TRUE

/// The emergency output on cell `C`: the ballast holds the lamp at its emergency level until the cell is down to what the dimmed level needs
/// (bulb_emergency_pow_min of bulb_emergency_pow_mul), then at that dimmed level until the cell runs out. Two levels, not a ramp: every station
/// light that loses power at the same moment changes level at the same moment, and each level change is a lighting update of every fixture in the dark.
/obj/machinery/light/proc/emergency_light_power(obj/item/cell/C)
	if(!C?.maxcharge || bulb_emergency_pow_mul <= bulb_emergency_pow_min)
		return bulb_emergency_pow_min
	return C.charge > emergency_dim_charge(C) ? bulb_emergency_pow_mul : bulb_emergency_pow_min

/// The cell charge below which the emergency output drops to its dimmed level.
/obj/machinery/light/proc/emergency_dim_charge(obj/item/cell/C)
	return bulb_emergency_pow_mul > 0 ? bulb_emergency_pow_min / bulb_emergency_pow_mul * C.maxcharge : 0

// ---- flicker ----

/obj/machinery/light/proc/flicker(amount = rand(10, 20), flicker_color)
	if(flickering) return
	if(on && status == LIGHT_OK)
		flicks_left = amount
		src.flicker_color = flicker_color
		flicker_original_color = brightness_color
		flicker_original_color_ns = brightness_color_ns
		set_flickering(TRUE)
		do_flicker()

/// The delay before the next flick.
/obj/machinery/light/proc/flicker_delay(datum/act/A)
	return rand(5, 15)

/// One flick of a flicker run; the run ends when the flicks run out or the bulb is no longer whole.
/obj/machinery/light/proc/do_flicker(datum/act/A)
	if(!flickering)
		return
	if(status != LIGHT_OK)
		set_flickering(FALSE)
		return
	set_on(!on)
	if(flicker_color && brightness_color != flicker_color)
		brightness_color = flicker_color
		brightness_color_ns = flicker_color
		refresh_light(0) //Yes. This is done here and then immediately followed up with another refresh. Why does it need that? I have no clue. But a single one does not work.
	refresh_light(0)
	if(!on) // Only play when the light turns off.
		play_sfx(src, SFX_EFFECTS_LIGHT_FLICKER)
	if(flicks_left > 0)
		flicks_left--
		return
	//All this happens after our final flicker.
	set_on((status == LIGHT_OK))
	brightness_color = flicker_original_color
	brightness_color_ns = flicker_original_color_ns
	refresh_light(0)
	refresh_light(0)
	set_flickering(FALSE)

/// An auto-flicker fixture waits on its cell for someone to see it.
/obj/machinery/light/proc/flicker_watching(datum/act/A)
	return auto_flicker && emergency_mode

/// An auto-flicker light on its cell flickers only while a player is near (radius 12); it rechecks every 2 seconds.
/obj/machinery/light/proc/auto_flicker_check(datum/act/A)
	if(!auto_flicker || !has_cell() || has_power() || !emergency_mode)
		return
	if(flickering)
		return
	if(check_for_player_proximity(src, radius = 12, ignore_ghosts = FALSE, ignore_afk = TRUE))
		seton(TRUE) // Lights must be on to flicker.
		flicker(5)
	else
		seton(FALSE) // Otherwise keep it dark and spooky for when someone shows up.

/// The AI's alt-click: the light flickers once.
/obj/machinery/light/proc/remote_flicker(datum/act/op/A)
	flicker(1)
	return OP_OK

// ---- the area's power: the fixture follows its area through the machine core's power_change() ----

/// Every channel change of the area, and every use of a light switch, reaches the fixture here.
/obj/machinery/light/power_change()
	. = ..()
	area_power_changed()

/// The fixture moved to another area: it follows that area's night shift and emergency lighting, and its power.
/obj/machinery/light/area_changed(area/old_area, area/new_area)
	rel_set(src, nameof(power_area), new_area)
	return ..()

/// The area's power_change() ran: act only if this light's power actually changed.
/obj/machinery/light/proc/area_power_changed()
	var/powered_now = !!has_power()
	if(powered_now == last_area_power)
		return
	last_area_power = powered_now
	if(powered_now)
		if(after_pending(src, "discharge"))
			settle_emergency_discharge()
			cancel_after(src, "discharge")
			emergency_discharge_started = 0
		set_emergency_mode(FALSE)
	else
		cancel_after(src, "recharge")
	seton(powered_now)
	if(powered_now)
		schedule_emergency_recharge()

/// The fixture stands in another area now (a turf moved with its lights): it reads that one.
/obj/machinery/light/proc/refresh_area()
	rel_set(src, nameof(power_area), get_area(src))
	area_power_changed()

/obj/machinery/light/proc/begin_emergency_discharge()
	if(!emergency_mode || !has_cell() || after_pending(src, "discharge"))
		return
	// Set the initial emergency appearance immediately, then account for charge in one batch when the light next has to change
	// (emergency_discharge_wait()).
	use_emergency_power(0)
	EXPIRY_STAMP(src, emergency_discharge_started, CLOCK_WORLD)
	after(src, emergency_discharge_wait(), PROC_REF(continue_emergency_discharge), key = "discharge", clock = CLOCK_WORLD)

/obj/machinery/light/proc/settle_emergency_discharge()
	if(!emergency_discharge_started || !has_cell())
		return
	var/elapsed = max(0, world.time - emergency_discharge_started)
	EXPIRY_STAMP(src, emergency_discharge_started, CLOCK_WORLD)
	var/amount = LIGHT_EMERGENCY_POWER_USE * (elapsed / (2 SECONDS))
	if(amount > 0)
		// A sustained draw over `elapsed`, settled in one batch: the cell sees its rate, not one surge.
		use_emergency_power(min(amount, emergency_cell().charge), elapsed / (1 SECOND))

/// The discharge batch is due: settle it and arm the next one, or end the emergency light.
/obj/machinery/light/proc/continue_emergency_discharge(datum/act/A)
	if(QDELETED(src))
		return
	if(has_power() || !emergency_mode || !has_cell())
		emergency_discharge_started = 0
		refresh_light(FALSE)
		return
	settle_emergency_discharge()
	if(!has_emergency_power(LIGHT_EMERGENCY_POWER_USE))
		emergency_discharge_started = 0
		refresh_light(FALSE)
		return
	after(src, emergency_discharge_wait(), PROC_REF(continue_emergency_discharge), key = "discharge", clock = CLOCK_WORLD)

/// How long the emergency cell can discharge before the light must change: its output drops to the dimmed level (emergency_light_power()) or the
/// cell runs out. The drain is settled in one batch then: a fixture in an unpowered area wakes twice over its cell's half hour, not every few
/// seconds (each wake is a timer, a redraw and a lighting update, and a station has a thousand such fixtures that all lose power together).
/obj/machinery/light/proc/emergency_discharge_wait()
	var/obj/item/cell/C = emergency_cell()
	if(!C?.maxcharge)
		return 2 SECONDS
	// The charge at which it runs out, or drops to the dimmed level if that comes first.
	var/target = LIGHT_EMERGENCY_POWER_USE
	var/dim = emergency_dim_charge(C)
	if(C.charge > dim && bulb_emergency_pow_mul > bulb_emergency_pow_min)
		target = max(target, dim)
	// LIGHT_EMERGENCY_POWER_USE every two seconds; one decisecond past the crossing, and never sooner than one drain step.
	return max((C.charge - target) / LIGHT_EMERGENCY_POWER_USE * (2 SECONDS) + 1, 2 SECONDS)

/obj/machinery/light/proc/schedule_emergency_recharge()
	if(!cell || cell.charge >= cell.maxcharge || !has_power() || after_pending(src, "recharge"))
		return
	// Charging is time based. Preserve the historical rate of 0.4 charge every two seconds while stable power is available.
	var/charge_steps = CEILING((cell.maxcharge - cell.charge) / (LIGHT_EMERGENCY_POWER_USE * 2), 1)
	after(src, charge_steps * (2 SECONDS), PROC_REF(finish_emergency_recharge), key = "recharge", clock = CLOCK_WORLD)

/obj/machinery/light/proc/finish_emergency_recharge(datum/act/A)
	if(QDELETED(src) || !cell || !has_power())
		return
	cell.give(cell.maxcharge - cell.charge)
	refresh_light(FALSE)

// ---- heat, breaking, mending ----

/// Heat behaviour rule: the tube breaks above 450 C.
/obj/machinery/light/proc/rule_break_light(datum/rule/rule)
	broken()

// explode the light

/obj/machinery/light/proc/explode()
	broken()	// break it first to give a warning
	after(src, 0.2 SECONDS, PROC_REF(explode_now))

/obj/machinery/light/proc/explode_now(datum/act/A)
	if(QDELETED(src))
		return
	explosion(get_turf(src), 0, 0, 2, 2)
	expire(1)

/// break the light and make sparks if was on
/obj/machinery/light/proc/broken(skip_sound_and_sparks = FALSE)
	if(status == LIGHT_EMPTY)
		return

	if(!skip_sound_and_sparks)
		if(status == LIGHT_OK || status == LIGHT_BURNED)
			play_sfx(src, SFX_EFFECTS_GLASSHIT)
		if(on)
			fx_sparks(src, 3)
	set_bulb_status(LIGHT_BROKEN)
	if(installed_light) // a latent bulb takes the fixture's status
		installed_light.set_status(status)
	refresh_light()

/obj/machinery/light/atom_break(damage_flag)
	. = ..()
	broken()

/obj/machinery/light/atom_fix()
	. = ..()
	fix()

/obj/machinery/light/proc/fix()
	if(status == LIGHT_OK)
		return
	set_bulb_status(LIGHT_OK)
	if(installed_light)
		installed_light.set_status(LIGHT_OK)
	set_on(1)
	refresh_light()

/// A power surge blows the light.
/obj/machinery/light/proc/surge_break()
	set_on(1)
	broken()

// the light item
// can be tube or bulb subtypes
// will fit into empty /obj/machinery/light of the corresponding type

/obj/item/light
	icon = 'icons/obj/lighting.dmi'
	force = 2
	throwforce = 5
	w_class = ITEMSIZE_TINY
	MATERIAL_BULK(MAT_STEEL, 60)

	///LIGHT_OK, LIGHT_BURNED or LIGHT_BROKEN
	var/status = LIGHT_OK
	///Base icon_state name to append suffixes for status
	var/base_state
	///Number of times switched on/off
	var/switchcount = 0
	///Is this light set to explode
	var/rigged = 0
	///The chance (prob()) that this light will be broken at roundstart
	var/broken_chance = 2

	///The raidus in turfs this light will reach. It will be at it's most dim this many turfs away.
	/// This is also used in power draw calculation for machinery/lights.
	var/brightness_range = 8
	///The light will fall off over more/less range based on this. The formula is complicated.
	var/brightness_power = 1
	///The color of the light emitted.
	var/brightness_color = LIGHT_COLOR_INCANDESCENT_TUBE

	///Replaces brightness_range during nightshifts.
	var/nightshift_range = 8
	///Replaces brightness_power during nightshifts.
	var/nightshift_power = 0.45
	///Replaces brightness_color during nightshifts.
	var/nightshift_color = LIGHT_COLOR_NIGHTSHIFT

	drop_sound = SFX_ITEMS_DROP_GLASS
	pickup_sound = SFX_ITEMS_PICKUP_GLASS

	var/init_brightness_range = 8
	var/init_brightness_power = 1
	var/init_nightshift_range = 8
	var/init_nightshift_power = 0.45

/obj/item/light/tube
	name = "light tube"
	desc = "A replacement light tube."
	icon_state = "ltube"
	base_state = "ltube"
	item_state = "c_tube"
	MATERIAL_BULK(MAT_GLASS, 100)
	init_brightness_range = 7
	init_brightness_power = 2

/obj/item/light/tube/large
	w_class = ITEMSIZE_SMALL
	name = "large light tube"
	icon_state = "ltube_large"
	base_state = "ltube_large"

	init_brightness_range = 15
	init_brightness_power = 4
	init_nightshift_range = 10
	init_nightshift_power = 1.5

/obj/item/light/bulb
	name = "light bulb"
	desc = "A replacement light bulb."
	icon_state = "lbulb"
	base_state = "lbulb"
	item_state = "contvapour"
	MATERIAL_BULK(MAT_GLASS, 100)
	brightness_color = LIGHT_COLOR_INCANDESCENT_BULB

	init_brightness_range = 5
	init_brightness_power = 1
	init_nightshift_range = 3
	init_nightshift_power = 0.5

// For 'floor lamps' in outdoor use and such
/obj/item/light/bulb/large
	name = "large light bulb"
	icon_state = "lbulb_large"
	base_state = "lbulb_large"

	init_brightness_range = 7
	init_brightness_power = 1.5
	init_nightshift_range = 4
	init_nightshift_power = 0.75

/obj/item/light/throw_impact(atom/hit_atom)
	..()
	shatter()

/obj/item/light/bulb/red
	brightness_range = 4
	color = "#da0205"
	brightness_color = "#da0205"
	init_brightness_range = 4

/obj/item/light/bulb/blue
	brightness_range = 4
	color = "#028bda"
	brightness_color = "#028bda"
	init_brightness_range = 4

/obj/item/light/bulb/fire
	name = "fire bulb"
	desc = "A replacement fire bulb."
	icon_state = "fbulb"
	base_state = "fbulb"
	item_state = "egg4"
	MATERIAL_BULK(MAT_GLASS, 100)

TRACKED(/obj/item/light, status)

CAPABILITIES(/obj/item/light)
	op("tune", tool(TOOL_MULTITOOL), light_tune_parts(TYPE_PROC_REF(/obj/item/light, tune_needs_number), TYPE_PROC_REF(/obj/item/light, tune_needs_color)), then(PROC_REF(tuned)))
	op("rig", item(/obj/item/reagent_containers/syringe), wait(0), then(PROC_REF(rigged_by_syringe)))
	op("shatter", at_target(), hostile(), when(cond_not(req(/obj/machinery/light, of = ON_TARGET))), wait(0), then(PROC_REF(shatter_on_hit)))
	on_change(nameof(status), ANY, then(PROC_REF(status_changed)))
	param(nameof(fixture_at_make), pos = 1, keep = FALSE)

/// The picture of a light shows its state.
/obj/item/light/draw(datum/look/look)
	..()
	switch(status)
		if(LIGHT_OK)
			look.state(base_state)
		if(LIGHT_BURNED)
			look.state("[base_state]-burned")
		if(LIGHT_BROKEN)
			look.state("[base_state]-broken")

/// The description follows the state.
/obj/item/light/proc/status_changed(datum/act/A)
	switch(status)
		if(LIGHT_OK)
			desc = "A replacement [name]."
		if(LIGHT_BURNED)
			desc = "A burnt-out [name]."
		if(LIGHT_BROKEN)
			desc = "A broken [name]."

/// The fixture the bulb was taken from (its constructor param, dropped after init).
/obj/item/light/var/tmp/obj/machinery/light/fixture_at_make

// ALLOW(init/INSTANCE_STATE): a bulb taken out of a fixture keeps its state, rigging and brightness
/obj/item/light/Initialize(mapload)
	. = ..()
	var/obj/machinery/light/fixture = fixture_at_make
	if(fixture)
		set_status(fixture.status)
		rigged = fixture.rigged
		switchcount = fixture.switchcount
		fixture.transfer_fingerprints_to(src)

		//shouldn't be necessary to copy these unless someone varedits stuff, but just in case
		brightness_range = fixture.brightness_range
		brightness_power = fixture.brightness_power
		brightness_color = fixture.brightness_color

// ---- tuning a light with a multitool ----
//
// A multitool asks what to change, then asks for the new number or colour. The second question depends on the first answer, so each kind of
// answer is a prompt of its own that fills itself from the first (prepare()) and is asked only for its choice (asks(when =)).

#define LIGHT_TUNE_RANGE "Normal Range"
#define LIGHT_TUNE_POWER "Normal Brightness"
#define LIGHT_TUNE_COLOR "Normal Color"
#define LIGHT_TUNE_NIGHT_RANGE "Nightshift Range"
#define LIGHT_TUNE_NIGHT_POWER "Nightshift Brightness"
#define LIGHT_TUNE_NIGHT_COLOR "Nightshift Color"

/// What the multitool does to a light (the bulb's own, or the fixture's, the same list): the choice, then the value it needs.
/proc/light_tune_parts(needs_number, needs_color)
	return list(
		wait(0),
		asks(/datum/prompt/choice, fields = list("question" = "What do you wish to change about this light?", "title" = "Light Adjustment", "choices" = list(LIGHT_TUNE_RANGE, LIGHT_TUNE_POWER, LIGHT_TUNE_COLOR, LIGHT_TUNE_NIGHT_RANGE, LIGHT_TUNE_NIGHT_POWER, LIGHT_TUNE_NIGHT_COLOR)), step = "what"),
		asks(/datum/prompt/number/light_tune, step = "number", when = needs_number),
		asks(/datum/prompt/color/light_tune, step = "color", when = needs_color))

/// The multitool's second question for a number: the bounds and the start follow what was chosen.
/datum/prompt/number/light_tune
	title = "Light Adjustment"

/datum/prompt/number/light_tune/prepare(datum/act/A)
	var/datum/act/op/O = A
	var/obj/item/light/B = light_tuned_bulb_of(O)
	var/datum/prompt/choice = O?.step_answer("what")
	if(!B || !choice)
		return
	switch(choice.value)
		if(LIGHT_TUNE_RANGE)
			question = "Choose the new range of the light! (1-[B.init_brightness_range])"
			default = B.init_brightness_range
			min_value = 1
			max_value = B.init_brightness_range
			step = 1
		if(LIGHT_TUNE_POWER)
			question = "Choose the new brightness of the light! (0.01 - [B.init_brightness_power])"
			default = B.init_brightness_power
			min_value = 0.01
			max_value = B.init_brightness_power
		if(LIGHT_TUNE_NIGHT_RANGE)
			question = "Choose the new range of the light! (1-[B.init_nightshift_range])"
			default = B.init_nightshift_range
			min_value = 1
			max_value = B.init_nightshift_range
			step = 1
		if(LIGHT_TUNE_NIGHT_POWER)
			question = "Choose the new brightness of the light! (0.01 - [B.init_nightshift_power])"
			default = B.init_nightshift_power
			min_value = 0.01
			max_value = B.init_nightshift_power

/// The multitool's second question for a colour.
/datum/prompt/color/light_tune
	question = "Choose a color to set the light to!"
	title = "Light Adjustment"

/datum/prompt/color/light_tune/prepare(datum/act/A)
	var/datum/act/op/O = A
	var/obj/item/light/B = light_tuned_bulb_of(O)
	var/datum/prompt/choice = O?.step_answer("what")
	if(!B || !choice)
		return
	default = (choice.value == LIGHT_TUNE_NIGHT_COLOR) ? B.nightshift_color : B.brightness_color

/// The bulb the op's holder is, or the bulb in the fixture it is.
/proc/light_tuned_bulb_of(datum/act/op/O)
	return light_tuned_bulb(O?.holder) // ALLOW(check_grep): the op's holder is the entity it runs on, never an admin holder

/// The bulb a multitool works on: the holder itself, or the bulb in a fixture.
/proc/light_tuned_bulb(datum/holder)
	var/obj/item/light/B = holder
	if(istype(B))
		return B
	var/obj/machinery/light/L = holder
	return istype(L) ? L.bulb() : null

/// The first answer is one of the number choices.
/obj/item/light/proc/tune_needs_number(datum/act/op/A)
	var/datum/prompt/choice = A.step_answer("what")
	return choice && (choice.value in list(LIGHT_TUNE_RANGE, LIGHT_TUNE_POWER, LIGHT_TUNE_NIGHT_RANGE, LIGHT_TUNE_NIGHT_POWER))

/obj/item/light/proc/tune_needs_color(datum/act/op/A)
	var/datum/prompt/choice = A.step_answer("what")
	return choice && (choice.value in list(LIGHT_TUNE_COLOR, LIGHT_TUNE_NIGHT_COLOR))

/// Applies the answers to this bulb; a bulb in a fixture tells the fixture.
/obj/item/light/proc/apply_tune(datum/act/op/A)
	var/datum/prompt/choice = A.step_answer("what")
	var/datum/prompt/value = A.step_answer("number") || A.step_answer("color")
	if(!choice || !value || isnull(value.value))
		return OP_REFUSED
	switch(choice.value)
		if(LIGHT_TUNE_RANGE)
			brightness_range = value.value
		if(LIGHT_TUNE_POWER)
			brightness_power = value.value
		if(LIGHT_TUNE_COLOR)
			brightness_color = value.value
		if(LIGHT_TUNE_NIGHT_RANGE)
			nightshift_range = value.value
		if(LIGHT_TUNE_NIGHT_POWER)
			nightshift_power = value.value
		if(LIGHT_TUNE_NIGHT_COLOR)
			nightshift_color = value.value
	if(istype(loc, /obj/machinery/light))
		var/obj/machinery/light/fixture = loc
		fixture.update_from_bulb(src)
		fixture.refresh_light()
		fixture.refresh_light() //Yes it has to double update...Don't ask me why. I think it's stupid.
	return OP_OK

/obj/item/light/proc/tuned(datum/act/op/A)
	return apply_tune(A)

/// A syringe emptied into a light: phoron rigs it to explode.
/obj/item/light/proc/rigged_by_syringe(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/reagent_containers/syringe/S = A.held

	to_chat(user, "You inject the solution into the [src].")

	if(S.reagents.has_reagent(REAGENT_ID_PHORON, 5))

		log_admin("LOG: [user.name] ([user.ckey]) injected a light with phoron, rigging it to explode.")
		message_admins("LOG: [user.name] ([user.ckey]) injected a light with phoron, rigging it to explode.")

		rigged = 1

	S.reagents.clear_reagents()
	return OP_OK

/// A light used to hit anything but a fixture shatters (it was an attempt to put it in a socket otherwise).
/obj/item/light/proc/shatter_on_hit(datum/act/op/A)
	shatter()
	return OP_OK

/obj/item/light/proc/shatter()
	if(status == LIGHT_OK || status == LIGHT_BURNED)
		src.visible_message(span_red("[name] shatters."),span_red("You hear a small glass object shatter."))
		set_status(LIGHT_BROKEN)
		force = 5
		sharp = TRUE
		play_sfx(src, SFX_EFFECTS_GLASSHIT)

//Lamp Shade
/obj/item/lampshade
	name = "lamp shade"
	desc = "A lamp shade for a lamp."
	icon = 'icons/obj/lighting.dmi'
	icon_state = "lampshade"
	w_class = ITEMSIZE_TINY

#undef LIGHT_BULB_TEMPERATURE
#undef LIGHTING_POWER_FACTOR
#undef LIGHT_EMERGENCY_POWER_USE

// I hate the way macros look stupid standing near lights. I don't care how absurd this looks.

/obj/machinery/light
	layer = BELOW_MOB_LAYER

// ition, to override the New() proc further below, since this is a lamp.
// ALLOW(init/INSTANCE_STATE): a floor lamp built from a frame starts without a cell or shade; a mapped one may get an emergency cell
/obj/machinery/light/flamp/Initialize(mapload)
	layer = initial(layer)
	. = ..()
	if(construct_at_make)
		start_with_cell = FALSE
		set_lamp_shade(0)
	else
		if(start_with_cell && !no_emergency)
			declare_emergency_cell()

/// The frame the light is built from (its constructor param, dropped after init).
/obj/machinery/light/var/tmp/obj/machinery/light_construct/construct_at_make

// create a new lighting fixture
// ALLOW(init/INSTANCE_STATE): a light built from a frame starts empty and faces the frame's way; a mapped one carries its bulb as data, and every light powers up
/obj/machinery/light/Initialize(mapload)
	. = ..()

	if(start_with_cell && !no_emergency)
		declare_emergency_cell()
	var/obj/machinery/light_construct/construct = construct_at_make
	if(construct)
		start_with_cell = FALSE
		set_bulb_status(LIGHT_EMPTY)
		construct_type = construct.type
		construct.transfer_fingerprints_to(src)
		set_dir(construct.dir)
	else
		latent_bulb = TRUE // the bulb is data until someone takes it (C5)
		var/obj/item/light/L = get_light_type_instance(light_type) //This is fine, but old code.
		update_from_bulb(L)
		if(prob(L.broken_chance))
			broken(1)

	set_on(powered())
	last_area_power = !!has_power()
	rel_set(src, nameof(power_area), get_area(src))
	refresh_light(0)
	// ition, so large mobs stop looking stupid in front of lights.
	if (dir == SOUTH) // Lights are backwards, SOUTH lights face north (they are on south wall)
		layer = ABOVE_MOB_LAYER

// Wall tube lights
/obj/item/light/tube
	brightness_range = 6
	brightness_power = 1

	nightshift_range = 6
	nightshift_power = 0.45

// Big tubes, unused I think
/obj/item/light/tube/large
	brightness_range = 8
	brightness_power = 2

	nightshift_range = 8
	nightshift_power = 1

// Small wall lights
/obj/item/light/bulb
	brightness_range = 4
	brightness_power = 1

	nightshift_range = 4
	nightshift_power = 0.45

// Floor lamps
/obj/item/light/bulb/large
	brightness_range = 6
	brightness_power = 1

	nightshift_range = 6
	nightshift_power = 0.45

// Floor tube lights

/obj/machinery/light/floortube
	icon_state = "floortube1"
	base_state = "floortube"
	desc = "A tube light set into a floor fixture."
	shows_alerts = FALSE
	plane = TURF_PLANE
	layer = ABOVE_TURF_LAYER
	construct_type = /obj/machinery/light_construct/floortube
	overlay_above_everything = FALSE

/obj/machinery/light/floortube/flicker
	auto_flicker = TRUE

// Big Flamp

/obj/machinery/light/bigfloorlamp
	icon = 'icons/obj/lighting32x64.dmi'
	icon_state = "big_flamp1"
	base_state = "big_flamp"
	desc = "A set of tube lights on a raised, solid fixture"
	shows_alerts = FALSE
	density = TRUE
	anchored = TRUE
	plane = MOB_PLANE
	layer = ABOVE_MOB_LAYER
	construct_type = /obj/machinery/light_construct/bigfloorlamp
	overlay_above_everything = TRUE

/obj/machinery/light/bigfloorlamp/flicker
	auto_flicker = TRUE

// Fairy lights

/obj/item/light/bulb/smol
	brightness_range = 1
	brightness_power = 0.5

	nightshift_range = 1
	nightshift_power = 0.25

/obj/machinery/light/small/fairylights
	icon = 'icons/obj/lighting.dmi'
	icon_state = "fairy_lights1"
	base_state = "fairy_lights"
	desc = "A set of lights on a long string of wire, anchored to the walls."
	light_type = /obj/item/light/bulb/smol
	shows_alerts = FALSE
	anchored = TRUE
	plane = ABOVE_MOB_PLANE
	layer = ABOVE_MOB_LAYER
	construct_type = null
	overlay_color = LIGHT_COLOR_INCANDESCENT_BULB
	overlay_above_everything = TRUE
	color = "#3e5064"

/obj/machinery/light/small/fairylights/broken(skip_sound_and_sparks = FALSE)
	return

/obj/machinery/light/small/fairylights/flicker
	auto_flicker = TRUE

/obj/machinery/light/lamppost
	icon = 'icons/obj/lighting32x64.dmi'
	icon_state = "lamppost1"
	base_state = "lamppost"
	desc = "A tall lampost that extends over an area"
	light_type = /obj/item/light/bulb
	shows_alerts = FALSE
	anchored = TRUE
	plane = ABOVE_MOB_PLANE
	layer = ABOVE_MOB_LAYER
	construct_type = null
	overlay_color = LIGHT_COLOR_INCANDESCENT_BULB
	overlay_above_everything = TRUE

/obj/item/light/bulb/torch
	brightness_range = 6
	color = "#fabf87"
	brightness_color = "#fabf87"
	init_brightness_range = 6

/obj/machinery/light/small/torch
	icon = 'icons/obj/lighting.dmi'
	name = "wall torch"
	icon_state = "torch1"
	base_state = "torch"
	desc = "A small torch held in a wall sconce."
	light_type = /obj/item/light/bulb/torch
	shows_alerts = FALSE
	anchored = TRUE
	plane = ABOVE_MOB_PLANE
	layer = ABOVE_MOB_LAYER
	construct_type = null
	overlay_color = LIGHT_COLOR_INCANDESCENT_BULB
	overlay_above_everything = TRUE

/// A wall torch swallows whatever is used on it (it is no socket to smash or fill).
CAPABILITIES(/obj/machinery/light/small/torch)
	without("insert")
	without("hit")
	op("swallow", item(/obj/item), answers(INTENT_USE, INTENT_ATTACK), wait(0), then(PROC_REF(swallowed)))

/obj/machinery/light/small/torch/proc/swallowed(datum/act/op/A)
	return OP_OK

/obj/machinery/light/broken
	icon_state = "tube-broken"

/obj/machinery/light/broken/Initialize(mapload)
	. = ..()
	broken()

/obj/machinery/light/broken/small
	icon_state = "bulb-broken"

/obj/machinery/light/broken/small/Initialize(mapload)
	. = ..()
	broken()

/// A floor lamp: a shade turns the switch into a hand toggle, the wrench bolts it down, the screwdriver takes the shade off. A silicon touch toggles
/// it too (it has no emergency lighting of its own to toggle).
CAPABILITIES(/obj/machinery/light/flamp)
	anchor()
	op("add_shade", item(/obj/item/lampshade), when(cond_not(nameof(lamp_shade))), wait(0), then(PROC_REF(shade_on)))
	op("remove_shade", tool(TOOL_SCREWDRIVER), when(nameof(lamp_shade)), priority(above("open_casing")), wait(0), then(PROC_REF(shade_off)))
	op("toggle", hand(), label("Toggle"), when(nameof(lamp_shade)), when(req_empty_hand()), priority(above("remove")), wait(0),
		needs(req(PROC_REF(has_light_in_fitting), because = PROC_REF(no_light_reason))), then(PROC_REF(toggle_lamp)))
	extend("open_casing", when(cond_not(nameof(lamp_shade))))

/obj/machinery/light/flamp/proc/has_light_in_fitting(datum/act/op/A)
	return status != LIGHT_EMPTY

/obj/machinery/light/flamp/proc/no_light_reason(datum/act/op/A)
	return /datum/msg/light/no_bulb

MSG_DEF_SELF(light/no_bulb, "There is no bulb in this light.")

/obj/machinery/light/flamp/proc/shade_on(datum/act/op/A)
	if(!consume(A.held, A.actor))
		return OP_REFUSED
	set_lamp_shade(1)
	return OP_OK

/obj/machinery/light/flamp/proc/shade_off(datum/act/op/A)
	playsound(src, A.held.usesound, 75, TRUE)
	act_message(A.actor, src, MSG_SELF("You remove %T%'s lamp shade."), MSG_OTHERS("[A.actor.name] removes %T%'s lamp shade."), MSG_BLIND("You hear a noise."))
	set_lamp_shade(FALSE)
	new /obj/item/lampshade(loc)
	return OP_OK

/obj/machinery/light/flamp/proc/toggle_lamp(datum/act/op/A)
	if(on)
		set_on(0)
		refresh_light()
	else
		set_on(has_power())
		refresh_light()
	return OP_OK

/// A multitool on a fixture with a working bulb tunes that bulb.
/obj/machinery/light/proc/bulb_can_be_tuned(datum/act/A)
	return status != LIGHT_BROKEN && status != LIGHT_EMPTY

/obj/machinery/light/proc/tune_needs_number(datum/act/op/A)
	var/datum/prompt/choice = A.step_answer("what")
	return choice && (choice.value in list(LIGHT_TUNE_RANGE, LIGHT_TUNE_POWER, LIGHT_TUNE_NIGHT_RANGE, LIGHT_TUNE_NIGHT_POWER))

/obj/machinery/light/proc/tune_needs_color(datum/act/op/A)
	var/datum/prompt/choice = A.step_answer("what")
	return choice && (choice.value in list(LIGHT_TUNE_COLOR, LIGHT_TUNE_NIGHT_COLOR))

/obj/machinery/light/proc/tuned(datum/act/op/A)
	var/obj/item/light/B = bulb()
	return B ? B.apply_tune(A) : OP_REFUSED
