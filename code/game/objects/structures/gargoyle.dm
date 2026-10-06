/obj/structure/gargoyle
	name = "statue"
	desc = "A very lifelike carving."
	density = TRUE
	anchored = TRUE
	var/initial_sleep
	var/initial_blind
	var/initial_is_shifted
	var/initial_lying
	var/initial_lying_prev
	var/wagging
	var/flapping
	max_integrity = 100
	// The integrity the statue started at when the mob was petrified (= mob vitality * endurance + 100).
	// Damage taken below this is transferred back to the mob on release; this is NOT
	// max_integrity, because a wounded mob petrifies into an already-weakened statue.
	var/original_int = 100
	var/stored_examine
	var/identifier = "statue"
	var/material = "stone"
	var/adjective = "hardens"
	var/list/tail_lower_dirs = list(NORTH, SOUTH) // ALLOW(instance_list): d: edited in place per instance (1 writers)
	var/image/tail_image

	var/can_revert = TRUE
	var/was_rayed = FALSE

/// The petrified mob (a relation view); the statue watches it every second while it holds one.
OM_FIELD_VIEW(/obj/structure/gargoyle, mob/living/carbon/human, WR_gargoyle, CHANGE_EXPLICIT)
DECLARE_PERIODIC_WHILE(/obj/structure/gargoyle, PERIODIC_SECOND, "WR_gargoyle")

CAPABILITIES(/obj/structure/gargoyle)
	param(nameof(petrified), pos = 1, keep = FALSE)
	param(nameof(ident_ovr), pos = 2)
	param(nameof(mat_ovr), pos = 3)
	param(nameof(adj_ovr), pos = 4)
	param(nameof(tint_ovr), pos = 5)
	param(nameof(can_revert), pos = 6)
	param(nameof(discard_clothes), pos = 7)

/// The human petrified, and what the statue overrides of their look (its constructor params).
/obj/structure/gargoyle/var/tmp/mob/living/carbon/human/petrified
/obj/structure/gargoyle/var/tmp/ident_ovr
/obj/structure/gargoyle/var/tmp/mat_ovr
/obj/structure/gargoyle/var/tmp/adj_ovr
/obj/structure/gargoyle/var/tmp/tint_ovr
/obj/structure/gargoyle/var/tmp/discard_clothes = FALSE

// ALLOW(init/INSTANCE_STATE): a gargoyle statue takes in the human it petrifies, with their look, tint and state
/obj/structure/gargoyle/Initialize(mapload)
	. = ..()
	var/mob/living/carbon/human/H = petrified
	if(isspace(loc) || isopenspace(loc))
		set_anchored(FALSE)
	if(!istype(H) || !isturf(H.loc))
		return
	var/datum/trait_state/gargoyle/comp = H.get_trait_state(/datum/trait_state/gargoyle)
	var/tint = "#FFFFFF"
	if(comp)
		EXPIRY_SET(comp, cooldown, (15 SECONDS), CLOCK_WORLD)
		rel_set(comp, nameof(comp.statue), src)
		comp.transformed = TRUE
		comp.paused = FALSE
		identifier = length(comp.identifier) > 0 ? comp.identifier : initial(identifier)
		material = length(comp.material) > 0 ? comp.material : initial(material)
		tint = length(comp.tint) > 0 ? comp.tint : initial(comp.tint)
		adjective = length(comp.adjective) > 0 ? comp.adjective : initial(adjective)
		if(copytext_char(adjective, -1) != "s")
			adjective += "s"
	rel_set(src, nameof(WR_gargoyle), H)

	if(H.get_effective_size(TRUE) < 0.5) // "So small! I can step over it!"
		set_density(FALSE)

	if(ident_ovr)
		identifier = ident_ovr
	if(mat_ovr)
		material = mat_ovr
	if(adj_ovr)
		adjective = adj_ovr
	if(tint_ovr)
		tint = tint_ovr

	if(H.tail_style?.clip_mask_state)
		tail_lower_dirs.Cut()
	else if(H.tail_style)
		tail_lower_dirs = H.tail_style.lower_layer_dirs.Copy()

	max_integrity = H.get_endurance() + 100
	original_int = H.vitality() * H.get_endurance() + 100
	update_integrity(original_int)
	name = "[identifier] of [H.name]"
	desc = "A very lifelike [identifier] made of [material]."
	stored_examine = H.examine(H)
	description_fluff = H.get_description_fluff()

	if(H?.buckled_to())
		var/atom/movable/_tmp_buck_10 = H?.buckled_to()
		_tmp_buck_10.unbuckle_mob(H, TRUE)

	//calculate our tints
	var/list/RGB = rgb2num(tint)

	var/colorr = rgb(RGB[1]*0.299, RGB[2]*0.299, RGB[3]*0.299)
	var/colorg = rgb(RGB[1]*0.587, RGB[2]*0.587, RGB[3]*0.587)
	var/colorb = rgb(RGB[1]*0.114, RGB[2]*0.114, RGB[3]*0.114)

	var/tint_color = list(colorr, colorg, colorb, "#000000")

	var/list/body_layers = HUMAN_BODY_LAYERS
	var/list/other_layers = HUMAN_OTHER_LAYERS
	for (var/i = 1; i <= length(H.overlays_standing); i++)
		if(i in other_layers)
			continue
		if(discard_clothes && !(i in body_layers))
			continue
		if(istype(H.overlays_standing[i], /image) && (i in body_layers))
			var/image/old_image = H.overlays_standing[i]
			var/image/new_image = image(old_image)
			if(i == TAIL_LOWER_LAYER || i == TAIL_UPPER_LAYER || i == TAIL_UPPER_LAYER_HIGH)
				tail_image = new_image
			new_image.color = tint_color
			new_image.layer = old_image.layer
			add_overlay(new_image)
		else
			if(!isnull(H.overlays_standing[i]))
				add_overlay(H.overlays_standing[i])

	initial_sleep = H.status_units(STAT_SLEEPING)
	initial_blind = H.status_units(STAT_BLINDED)
	initial_is_shifted = H.is_shifted
	transform = H.transform
	layer = H.layer
	pixel_x = H.pixel_x
	pixel_y = H.pixel_y
	dir = H.dir
	initial_lying = H.lying
	initial_lying_prev = H.lying_prev
	H.set_sdisabilities(H.sdisabilities | MUTE)
	if(H.appearance_flags & PIXEL_SCALE)
		appearance_flags |= PIXEL_SCALE
	wagging = H.wagging
	flapping = H.flapping
	H.toggle_tail(FALSE, FALSE)
	H.toggle_wing(FALSE, FALSE)
	act_message(H, null, MSG_SELF(span_warning("Your skin abruptly [adjective] as you turn to [material]!")), \
		MSG_OTHERS(span_warning("%U%'s skin rapidly [adjective] as they turn to [material]!")))
	H.forceMove(src)
	H.status_set(STAT_BLINDED, 0)
	H.status_set(STAT_SLEEPING, 0)
	H.canmove = 0

// the petrified gargoyle reverts, or crumbles.
/obj/structure/gargoyle/on_destroy(force)
	var/mob/living/carbon/human/gargoyle = WR_gargoyle
	if(!gargoyle)
		..()
		return
	if(can_revert)
		unpetrify(deleting = FALSE) //don't delete if we're already deleting!
	else
		visible_message(span_warning("The [identifier] loses shape and crumbles into a pile of [material]!"))
	..()

/obj/structure/gargoyle/periodic_step()
	var/mob/living/carbon/human/gargoyle = WR_gargoyle
	if(!gargoyle)
		consume(src)
		return
	if(gargoyle.stat == DEAD) //died while in statue state.
		unpetrify(deal_damage = TRUE, deleting = TRUE)
		return
	if(gargoyle.loc != src)
		can_revert = TRUE //something's gone wrong, they escaped, lets not qdel them
		unpetrify(deal_damage = FALSE, deleting = TRUE)

/// Overheating (above 1600 C): the stone cracks.
/obj/structure/gargoyle/apply_heat_damage(amount)
	damage(amount * 0.1)

/obj/structure/gargoyle/examine_icon()
	var/icon/examine_icon = icon(icon=src.icon, icon_state=src.icon_state, dir=SOUTH, frame=1, moving=0)
	examine_icon.MapColors(rgb(77,77,77), rgb(150,150,150), rgb(28,28,28), rgb(0,0,0))
	return examine_icon

/obj/structure/gargoyle/get_mechanics_info(list/additional_information)
	var/mob/living/carbon/human/gargoyle = WR_gargoyle
	if(gargoyle)
		if(isspace(loc) || isopenspace(loc))
			return
		return "It can be [anchored ? "un" : ""]anchored with a wrench."

/obj/structure/gargoyle/examine(mob/user)
	. = ..()
	var/mob/living/carbon/human/gargoyle = WR_gargoyle
	if(gargoyle && stored_examine)
		. += "The [identifier] seems to have a bit more to them..."
		. += stored_examine
	return

/obj/structure/gargoyle/proc/unpetrify(deal_damage = TRUE, deleting = FALSE)
	if(deleting && loc?.release_refusal(src))
		return
	var/mob/living/carbon/human/gargoyle = WR_gargoyle
	if(!gargoyle)
		return
	var/datum/trait_state/gargoyle/comp = gargoyle.get_trait_state(/datum/trait_state/gargoyle)
	if(comp)
		EXPIRY_SET(comp, cooldown, (15 SECONDS), CLOCK_WORLD)
		rel_clear(comp, nameof(comp.statue))
		comp.transformed = FALSE
	else
		if(was_rayed)
			revoke(gargoyle, granted_verb(/mob/living/carbon/human/proc/gargoyle_transformation), src)
	if(gargoyle.loc == src)
		gargoyle.forceMove(loc)
		gargoyle.transform = transform
		gargoyle.pixel_x = pixel_x
		gargoyle.pixel_y = pixel_y
		gargoyle.is_shifted = initial_is_shifted
		gargoyle.dir = dir
		gargoyle.lying = initial_lying
		gargoyle.lying_prev = initial_lying_prev
		gargoyle.toggle_tail(wagging, FALSE)
		gargoyle.toggle_wing(flapping, FALSE)
	gargoyle.set_sdisabilities(gargoyle.sdisabilities & (~MUTE))
	gargoyle.status_set(STAT_BLINDED, initial_blind)
	gargoyle.status_set(STAT_SLEEPING, initial_sleep)
	gargoyle.canmove = 1
	gargoyle.update_canmove()
	var/hurtmessage = ""
	if(deal_damage)
		if(get_integrity() < original_int)
			var/f = (original_int - get_integrity()) / 10
			for (var/x in 1 to 10)
				gargoyle.injure(INJURY_BLUNT, f, ran_zone(), src)
			hurtmessage = " " + span_bold("You feel your body take the damage that was dealt while being [material]!")
	alpha = 0
	act_message(gargoyle, null, MSG_SELF(span_warning("Your skin reverts, freeing your movement once more![hurtmessage]")), \
		MSG_OTHERS(span_warning("%U%'s skin rapidly reverts, returning them to normal!")))
	gargoyle = null
	if(deleting)
		consume(src)

/obj/structure/gargoyle/return_air()
	return return_air_for_internal_lifeform()

/obj/structure/gargoyle/return_air_for_internal_lifeform(mob/living/lifeform)
	var/air_type = /datum/gas_mixture/belly_air
	if(istype(lifeform))
		air_type = lifeform.get_perfect_belly_air_type()
	var/air = new air_type(1000)
	return air

/obj/structure/gargoyle/proc/damage(amount)
	if(was_rayed)
		return //gargoyle quick regenerates, the others don't, so let's not have them getting too damaged
	take_damage(amount, BRUTE, MELEE, sound_effect = FALSE)

/obj/structure/gargoyle/attack_generic(mob/user, damage, attack_message = "hits")
	user.do_attack_animation(src)
	act_message(user, src, others = span_danger("%U% [attack_message] %T%!"))
	damage(damage)

/obj/structure/gargoyle/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_item/gargoyle_item,
	)
	..()

/// Old attackby: anchor with a wrench, feed the gargoyle's vore mode, or take a hit.
/datum/interaction/entry_item/gargoyle_item
	id = "gargoyle_item"
	name = "Use"
	effect = /obj/structure/gargoyle/proc/interaction_item

/obj/structure/gargoyle/proc/interaction_item(mob/living/user, obj/item/W, datum/interaction/interaction)
	var/mob/living/carbon/human/gargoyle = WR_gargoyle
	if(W.has_tool_quality(TOOL_WRENCH))
		if(isspace(loc) || isopenspace(loc))
			to_chat(user, span_warning("You can't anchor that here!"))
			set_anchored(FALSE)
			return TRUE
		var/was_anchored = anchored
		use_tool(user, W, src, delay = 2 SECONDS, quality = TOOL_WRENCH, volume = 50, receiver = src, on_done = PROC_REF(attackby_tool_done), done_args = list(user, was_anchored))
	else if(!isrobot(user) && gargoyle && gargoyle.vore_selected && gargoyle.trash_catching)
		if(istype(W, /obj/item/grab) || istype(W, /obj/item/holder))
			gargoyle.vore_attackby(W, user, I_HELP) // feeding the statue its catch is a peaceful use
			return TRUE
		if(gargoyle.adminbus_trash || is_type_in_list(W, GLOB.edible_trash) && W.trash_eatable && !is_type_in_list(W, GLOB.item_vore_blacklist))
			to_chat(user, span_warning("You slip [W] into [gargoyle]'s [lowertext(gargoyle.vore_selected.name)] ."))
			user.drop_item()
			gargoyle.vore_selected.nom_atom(W)
			return TRUE
	else if(!(W.flags & NOBLUDGEON))
		user.setClickCooldown(user.get_attack_speed(W))
		if(W.obj_damage_type())
			user.do_attack_animation(src)
			playsound(src, W.hitsound, 50, 1)
			damage(W.force)
	return TRUE

/obj/structure/gargoyle/proc/attackby_tool_done(mob/living/user, was_anchored)
	to_chat(user, span_notice("You [was_anchored ? "un" : ""]anchor the [src]."))
	set_anchored(!anchored)

/obj/structure/gargoyle/set_dir(new_dir)
	. = ..()
	if(. && tail_image)
		cut_overlay(tail_image)
		tail_image.layer = BODY_LAYER + ((dir in tail_lower_dirs) ? TAIL_LOWER_LAYER : TAIL_UPPER_LAYER)
		add_overlay(tail_image)

/obj/structure/gargoyle/hitby(atom/movable/source, datum/thrownthing/throwingdatum)
	var/mob/living/carbon/human/gargoyle = WR_gargoyle
	if(!gargoyle)
		return
	if(isitem(source) && gargoyle.vore_selected && gargoyle.trash_catching)
		var/obj/item/I = source
		if(gargoyle.adminbus_trash || is_type_in_list(I, GLOB.edible_trash) && I.trash_eatable && !is_type_in_list(I, GLOB.item_vore_blacklist))
			gargoyle.hitby(source, throwingdatum)
			return
	else if(isliving(source))
		var/mob/living/L = source
		if(can_throw_vore(gargoyle, L))
			var/drop_prey_temp = FALSE
			if(gargoyle.can_be_drop_prey)
				drop_prey_temp = TRUE
				gargoyle.can_be_drop_prey = FALSE //Making sure the original gargoyle body is not the one getting throwvored instead.
			gargoyle.hitby(L, throwingdatum)
			if(drop_prey_temp)
				gargoyle.can_be_drop_prey = TRUE
			return
	return ..()

