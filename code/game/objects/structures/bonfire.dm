// LINDA atmospherics rewrite (commit 6fdac16ef1). gas_mixture var accesses (e.g. mix.total_moles) converted to proc calls (mix.total_moles()) for the LINDA engine API. Bulk rewrite by tools/verdigris/linda_rewrite_chomp_atmos.py.
// Bracketed at file-header rather than per-hunk because the
// edits are mechanical and span the whole file; the commit SHA
// is the source of truth for per-line diff context.

/obj/structure/bonfire
	name = "bonfire"
	desc = "For grilling, broiling, charring, smoking, heating, roasting, toasting, simmering, searing, melting, and occasionally burning things."
	icon = 'icons/obj/structures.dmi'
	icon_state = "bonfire"
	density = FALSE
	anchored = TRUE
	buckle_lying = FALSE
	EXPIRY_DECLARE(next_fuel_consumption) // world.time of when next item in fuel list gets eatten to sustain the fire.
	var/grill = FALSE
	var/datum/material/material
	var/set_temperature = T0C + 30	//K
	var/heating_power = 80000
	resistance_flags = FIRE_PROOF

/obj/structure/bonfire/var/burning = FALSE
TRACKED(/obj/structure/bonfire, burning)
CAPABILITIES(/obj/structure/bonfire)
	slot(CONTAINER_SLOT_FUEL)
	every(2 SECONDS, then(PROC_REF(bonfire_step)), when = nameof(burning))
	param(nameof(fuel_material), pos = 1, apply = PROC_REF(build_of))
	op("build", item(/obj/item/stack/rods), label("Use"), when(cond_not(nameof(can_buckle))), when(cond_not(nameof(grill))),
		asks(/datum/prompt/choice, fields = list("title" = "Bonfire", "question" = "What would you like to construct?", "choices" = list("Stake", "Grill"), "timeout" = 0)),
		then(PROC_REF(construction_chosen)))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))
	op("hand", hand(), label("Use"), then(PROC_REF(interaction_hand)))
	op("dismantle", hand(), label("Dismantle"), priority(OP_PRIORITY_TAKE_OUT), when(req_empty_hand()), when(req(PROC_REF(ready_to_dismantle))),
		needs(req_bool(PROC_REF(not_burning), because = MSG(bonfire/still_burning))), begins(MSG(bonfire/dismantling)), wait(5 SECONDS), then(PROC_REF(dismantle_done)))

MSG_DEF(bonfire/dismantling, "You start dismantling %T%.", "%U% starts dismantling %T%.")
MSG_DEF_SELF(bonfire/still_burning, span_warning("%T% is still burning. Extinguish it first if you want to dismantle it."))

TYPE_TABLE_DECLARE(/obj/structure/bonfire, forced_bonfire_material, null)

/// The fuel's material (its constructor param, or the type's forced one).
/obj/structure/bonfire/var/fuel_material = MAT_WOOD

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm).
/obj/structure/bonfire/proc/build_of(material_name)
	var/forced_material = TYPE_TABLE_GET(src, forced_bonfire_material)
	if(forced_material)
		material_name = forced_material
	material = get_material_by_name("[material_name || MAT_WOOD]")
	if(!material)
		stack_trace("Material of type: [material_name] does not exist.")
		spent(src)
		return
	color = material.icon_colour

// Blue wood.
TYPE_TABLE(/obj/structure/bonfire/sifwood, forced_bonfire_material, MAT_SIFWOOD)

CAPABILITIES(/obj/structure/bonfire/permanent)
	after_init(0, then(PROC_REF(init_ignite)))

/obj/structure/bonfire/permanent/proc/init_ignite(datum/act/timer/A)
	ignite()


TYPE_TABLE(/obj/structure/bonfire/permanent/sifwood, forced_bonfire_material, MAT_SIFWOOD)

// ition Start
TRACKED(/obj/structure/bonfire, grill)

/obj/structure/bonfire/examine(mob/user)
	. = ..()
	var/X = get_fuel_amount()
	. += "The fire has [X] logs in it."
	if(grill)
		. += "[src] has a crude grill plate over it."
	if(can_buckle)
		. += "[src] has a makeshift stake built in it, perfect for witches and space templars."
// ition end

/// Old attackby: add wood or logs as fuel, or ignite it with a hot item.
/obj/structure/bonfire/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(istype(W, /obj/item/stack/material/wood) || istype(W, /obj/item/stack/material/log) )
		add_fuel(W, user)

	else if(W.is_hot())
		ignite()
	return OP_OK

/// Old attackby with rods: build a stake or a grill into it (the rods held throughout).
/obj/structure/bonfire/proc/construction_chosen(datum/act/op/A)
	var/datum/prompt/P = A.answer
	if(!P)
		return OP_OK
	var/mob/user = A.actor
	var/obj/item/stack/rods/R = A.held
	switch(P.value)
		if("Stake")
			R.use(1)
			set_can_buckle(TRUE)
			buckle_require_restraints = TRUE
			to_chat(user, span_notice("You add a rod to \the [src]."))
			var/mutable_appearance/rod_underlay = mutable_appearance('icons/obj/structures.dmi', "bonfire_rod")
			rod_underlay.pixel_y = 16
			rod_underlay.appearance_flags = RESET_COLOR|PIXEL_SCALE|TILE_BOUND
			underlays += rod_underlay
		if("Grill")
			R.use(1)
			set_grill(TRUE)
			to_chat(user, span_notice("You add a grill to \the [src]."))
	return OP_OK

/// Old attack_hand: take the fuel out (an empty bonfire is taken apart by the dismantle op).
/obj/structure/bonfire/proc/interaction_hand(datum/act/op/A)
	remove_fuel(A.actor)
	return OP_OK

/// An empty bonfire can be taken apart (what lies in it is fixed while the click is decided).
/obj/structure/bonfire/proc/ready_to_dismantle(datum/act/op/A)
	return read_once(get_fuel_amount()) ? MSG(req_failed) : null

/obj/structure/bonfire/permanent/ready_to_dismantle(datum/act/op/A)
	return null

/obj/structure/bonfire/proc/not_burning(datum/act/op/A)
	return !burning

/obj/structure/bonfire/proc/dismantle_done(datum/act/op/A)
	var/mob/user = A.actor
	for(var/i = 1 to 5)
		material.place_dismantled_product(get_turf(src))
	act_message(user, src, MSG_SELF("You dismantle %T%."), MSG_OTHERS("%U% dismantles down %T%."))
	consume(src, user)
	return OP_OK

/obj/structure/bonfire/proc/get_fuel_amount()
	var/F = 0
	for(var/kind in slot_kinds(CONTAINER_SLOT_FUEL, /obj/item/stack/material))
		if(ispath(kind, /obj/item/stack/material/wood))
			F += 0.5
		if(ispath(kind, /obj/item/stack/material/log))
			F += 1.0
	return F

/obj/structure/bonfire/permanent/get_fuel_amount()
	return 10

/obj/structure/bonfire/proc/remove_fuel(mob/user)
	if(get_fuel_amount())
		var/atom/movable/AM = pop(contents)
		AM.forceMove(get_turf(src))
		to_chat(user, span_notice("You take \the [AM] out of \the [src] before it has a chance to burn away."))

/obj/structure/bonfire/proc/add_fuel(atom/movable/new_fuel, mob/user)
	if(get_fuel_amount() >= 10)
		to_chat(user, span_warning("\The [src] already has enough fuel!"))
		return FALSE
	if(istype(new_fuel, /obj/item/stack/material/wood) || istype(new_fuel, /obj/item/stack/material/log) )
		var/obj/item/stack/F = new_fuel
		var/obj/item/stack/S = F.split(1)
		if(S)
			move_into(src, null, S, user)
			to_chat(user, span_warning("You add \the [new_fuel] to \the [src]."))
			return TRUE
		return FALSE
	else
		to_chat(user, span_warning("\The [src] needs raw wood to burn, \a [new_fuel] won't work."))
		return FALSE

/obj/structure/bonfire/permanent/add_fuel(mob/user)
	to_chat(user, span_warning("\The [src] has plenty of fuel and doesn't need more fuel."))

/obj/structure/bonfire/proc/consume_fuel(obj/item/stack/consumed_fuel)
	if(!istype(consumed_fuel))
		consume(consumed_fuel) // Don't know, don't care.
		return FALSE

	if(istype(consumed_fuel, /obj/item/stack/material/log))
		EXPIRY_SET(src, next_fuel_consumption, 6 MINUTES, CLOCK_WORLD)
		consume(consumed_fuel)
		return TRUE

	else if(istype(consumed_fuel, /obj/item/stack/material/wood)) // One log makes two planks of wood.
		EXPIRY_SET(src, next_fuel_consumption, 3 MINUTE, CLOCK_WORLD)
		consume(consumed_fuel)
		return TRUE
	return FALSE

/obj/structure/bonfire/permanent/consume_fuel()
	return TRUE

/obj/structure/bonfire/proc/check_oxygen()
	var/datum/gas_mixture/G = loc.return_air()
	if(LINDA_GAS_AMT(G, GAS_O2) < 1)
		return FALSE
	return TRUE


/obj/structure/bonfire/extinguish()
	. = ..()
	if(burning)
		set_burning(FALSE)
		visible_message(span_infoplain(span_bold("\The [src]") + " stops burning."))

/obj/structure/bonfire/proc/ignite()
	if(!burning && get_fuel_amount())
		set_burning(TRUE)
		visible_message(span_warning("\The [src] starts burning!"))

/obj/structure/bonfire/proc/burn_bonfire()
	var/turf/current_location = get_turf(src)
	current_location.hotspot_expose(1000, 500)
	for(var/A in current_location)
		if(A == src)
			continue
		if(isobj(A))
			var/obj/O = A
			O.fire_act(1000, 500)
		else if(isliving(A) && get_fuel_amount() > 4)
			var/mob/living/L = A
			if(!(L.is_incorporeal()))
				L.adjust_fire_stacks(get_fuel_amount() / 4)
				L.ignite_mob()

/obj/structure/bonfire/draw(datum/look/look)
	..()
	if(burning)
		var/fuel = get_fuel_amount()
		var/state
		switch(fuel)
			if(0 to 4.5)
				state = "bonfire_warm"
			if(4.6 to 10)
				state = "bonfire_hot"
		look.overlay(look_appearance(icon, state, appearance_flags = RESET_COLOR))
		if(has_buckled_mobs() && fuel >= 5)
			look.overlay(look_overlay_image(icon, "bonfire_intense", layer = MOB_LAYER + 0.1, pixel_y = 13, appearance_flags = RESET_COLOR))
		var/light_strength = max(fuel / 2, 2)
		look.light(light_strength, light_strength, "#FF9933")
	else
		look.light_off()
	if(grill)
		look.overlay(look_appearance(icon, "bonfire_grill", appearance_flags = RESET_COLOR))

/obj/structure/bonfire/proc/bonfire_step(datum/act/timer/A)
	if(!check_oxygen())
		extinguish()
		return
	if(EXPIRY_EXPIRED(src, next_fuel_consumption, CLOCK_WORLD))
		if(!consume_fuel(pop(contents)))
			extinguish()
			return
	if(!grill)
		burn_bonfire()

	if(burning)
		var/W = get_fuel_amount()
		if(W >= 5)
			var/datum/gas_mixture/env = loc.return_air()
			if(env && abs(env.return_temperature() - set_temperature) > 0.1)
				var/transfer_moles = 0.25 * env.total_moles()
				var/datum/gas_mixture/removed = env.remove(transfer_moles)

				if(removed)
					var/heat_transfer = removed.get_thermal_energy_change(set_temperature)
					if(heat_transfer > 0)
						heat_transfer = min(heat_transfer , heating_power)

						heat_add(removed, heat_transfer, HEAT_SOURCE_FIRE)

				for(var/mob/living/L in view(3, src))
					L.apply_body_effect(/datum/body_effect/endothermic, 10 SECONDS, null, TRUE)

				for(var/obj/item/stack/wetleather/WL in view(2, src))
					if(WL.wetness >= 0)
						WL.dry()
						continue

					WL.set_wetness(max(0, WL.wetness - rand(1, 4)))

				env.merge(removed)

/// Heat behaviour rule: fire lights the bonfire.
/obj/structure/bonfire/proc/rule_light(datum/rule/rule)
	ignite()

/obj/structure/bonfire/water_act(amount)
	if(prob(amount * 10))
		extinguish()

/obj/structure/bonfire/post_buckle_mob(mob/living/M)
	if(M?.buckled_to() == src) // Just buckled someone
		M.pixel_y += 13
	else // Just unbuckled someone
		M.pixel_y -= 13

/obj/structure/fireplace //more like a space heater than a bonfire. A cozier alternative to both.
	name = "fireplace"
	desc = "The sound of the crackling hearth reminds you of home."
	icon = 'icons/obj/fireplace.dmi'
	icon_state = "fireplace"
	density = TRUE
	anchored = TRUE
	EXPIRY_DECLARE(next_fuel_consumption)
	var/set_temperature = T0C + 20	//K
	var/heating_power = 40000
	resistance_flags = FIRE_PROOF

/obj/structure/fireplace/var/burning = FALSE
TRACKED(/obj/structure/fireplace, burning)
CAPABILITIES(/obj/structure/fireplace)
	slot(CONTAINER_SLOT_FUEL)
	every(2 SECONDS, then(PROC_REF(fireplace_step)), when = nameof(burning))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))
	op("hand", hand(), label("Use"), then(PROC_REF(interaction_hand)))

/obj/structure/fireplace/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(istype(W, /obj/item/stack/material/wood) || istype(W, /obj/item/stack/material/log) )
		add_fuel(W, user)

	else if(W.is_hot())
		ignite()
	return TRUE

/obj/structure/fireplace/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	if(get_fuel_amount())
		remove_fuel(user)
	return TRUE

/obj/structure/fireplace/proc/get_fuel_amount()
	var/F = 0
	for(var/kind in slot_kinds(CONTAINER_SLOT_FUEL, /obj/item/stack/material))
		if(ispath(kind, /obj/item/stack/material/wood))
			F += 0.5
		if(ispath(kind, /obj/item/stack/material/log))
			F += 1.0
	return F

/obj/structure/fireplace/proc/remove_fuel(mob/user)
	if(get_fuel_amount())
		var/atom/movable/AM = pop(contents)
		AM.forceMove(get_turf(src))
		to_chat(user, span_notice("You take \the [AM] out of \the [src] before it has a chance to burn away."))

/obj/structure/fireplace/proc/add_fuel(atom/movable/new_fuel, mob/user)
	if(get_fuel_amount() >= 10)
		to_chat(user, span_warning("\The [src] already has enough fuel!"))
		return FALSE
	if(istype(new_fuel, /obj/item/stack/material/wood) || istype(new_fuel, /obj/item/stack/material/log) )
		var/obj/item/stack/F = new_fuel
		var/obj/item/stack/S = F.split(1)
		if(S)
			move_into(src, null, S, user)
			to_chat(user, span_warning("You add \the [new_fuel] to \the [src]."))
			return TRUE
		return FALSE
	else
		to_chat(user, span_warning("\The [src] needs raw wood to burn, \a [new_fuel] won't work."))
		return FALSE

/obj/structure/fireplace/proc/consume_fuel(obj/item/stack/consumed_fuel)
	if(!istype(consumed_fuel))
		consume(consumed_fuel) // Don't know, don't care.
		return FALSE

	if(istype(consumed_fuel, /obj/item/stack/material/log))
		EXPIRY_SET(src, next_fuel_consumption, 6 MINUTES, CLOCK_WORLD)
		consume(consumed_fuel)
		return TRUE

	else if(istype(consumed_fuel, /obj/item/stack/material/wood)) // One log makes two planks of wood.
		EXPIRY_SET(src, next_fuel_consumption, 3 MINUTES, CLOCK_WORLD)
		consume(consumed_fuel)
		return TRUE
	return FALSE

/obj/structure/fireplace/proc/check_oxygen()
	var/datum/gas_mixture/G = loc.return_air()
	if(LINDA_GAS_AMT(G, GAS_O2) < 1)
		return FALSE
	return TRUE

/obj/structure/fireplace/extinguish()
	. = ..()
	if(burning)
		set_burning(FALSE)
		visible_message(span_infoplain(span_bold("\The [src]") + " stops burning."))

/obj/structure/fireplace/proc/ignite()
	if(!burning && get_fuel_amount())
		set_burning(TRUE)
		visible_message(span_warning("\The [src] starts burning!"))

/obj/structure/fireplace/proc/burn_bonfire()
	var/turf/current_location = get_turf(src)
	current_location.hotspot_expose(1000, 500)
	for(var/A in current_location)
		if(A == src)
			continue
		if(isobj(A))
			var/obj/O = A
			O.fire_act(1000, 500)

/obj/structure/fireplace/draw(datum/look/look)
	..()
	look_parts(look)

/// What this chain's providers drew: each type's own part of the look, a subtype replacing or extending it (..()).
/obj/structure/fireplace/proc/look_parts(datum/look/look)
	var/drawn_state = look.state_so_far(src)
	if(burning)
		var/state
		switch(get_fuel_amount())
			if(0 to 1)
				state = "[drawn_state]_fire0"
			if(2 to 4)
				state = "[drawn_state]_fire1"
			if(4 to 6)
				state = "[drawn_state]_fire2"
			if(6 to 8)
				state = "[drawn_state]_fire3"
			if(8 to 10)
				state = "[drawn_state]_fire4"
		look.overlay(mutable_appearance(icon, state))
		look.overlay(emissive_appearance(icon, state))
		look.overlay(mutable_appearance(icon, "[drawn_state]_glow"))
		look.overlay(emissive_appearance(icon, "[drawn_state]_glow"))

		var/light_strength = max(get_fuel_amount() / 2, 2)
		look.light(light_strength, light_strength, "#FF9933")
	else
		look.light_off()

/obj/structure/fireplace/proc/fireplace_step(datum/act/timer/A)
	if(!check_oxygen())
		extinguish()
		return
	if(EXPIRY_EXPIRED(src, next_fuel_consumption, CLOCK_WORLD))
		if(!consume_fuel(pop(contents)))
			extinguish()
			return

	if(burning)
		var/W = get_fuel_amount()
		if(W >= 5)
			var/datum/gas_mixture/env = loc.return_air()
			if(env && abs(env.return_temperature() - set_temperature) > 0.1)
				var/transfer_moles = 0.25 * env.total_moles()
				var/datum/gas_mixture/removed = env.remove(transfer_moles)

				if(removed)
					var/heat_transfer = removed.get_thermal_energy_change(set_temperature)
					if(heat_transfer > 0)
						heat_transfer = min(heat_transfer , heating_power)

						heat_add(removed, heat_transfer, HEAT_SOURCE_FIRE)

				env.merge(removed)

/// Heat behaviour rule: fire lights the fireplace.
/obj/structure/fireplace/proc/rule_light(datum/rule/rule)
	ignite()

/obj/structure/fireplace/water_act(amount)
	if(prob(amount * 10))
		extinguish()


/obj/structure/fireplace/barrel
	name = "barrel fire pit"
	desc = "Seems like this barrel might make an ideal fire pit."
	icon_state = "barrelfire"
	density = TRUE
	anchored = FALSE

/obj/structure/fireplace/barrel/look_parts(datum/look/look)
	if(burning)
		look.state("[initial(icon_state)]1")
		var/light_strength = max(get_fuel_amount() / 2, 2)
		look.light(light_strength, light_strength, "#FF9933")
	else
		look.state(initial(icon_state))
		look.light_off()
