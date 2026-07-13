// Gameplay objects the expedition missions spawn and track.
//
// Visuals inherit their parent type's icon for now (a guaranteed-valid sprite,
// so the build never breaks on a missing .dmi). Bespoke art is a polish pass.

// ---------------------------------------------------------------------------
// Retrieval target: a precursor relic the crew must carry back to the pad.
// ---------------------------------------------------------------------------
/obj/item/expedition_artifact
	name = "precursor relic"
	desc = "An angular, faintly humming artifact of unknown origin. Xenoarchaeology will want this back at the station."
	w_class = ITEMSIZE_NORMAL
	throwforce = 5

// ---------------------------------------------------------------------------
// Rescue target: a sealed stasis capsule holding a stranded surveyor. Unanchored
// so the crew can drag it back to the pad.
// ---------------------------------------------------------------------------
/obj/structure/expedition_survivor_pod
	name = "stasis capsule"
	desc = "A battered emergency stasis capsule. The occupant is alive but won't last forever — get it back to the station."
	density = TRUE
	anchored = FALSE

// ---------------------------------------------------------------------------
// Survey target: a marker the crew records data from on touch. Once every
// marker is scanned the survey mission completes.
// ---------------------------------------------------------------------------
/obj/structure/expedition_survey_beacon
	name = "survey marker"
	desc = "A geological survey marker. Its readings must be logged with a survey scanner or a handheld analyzer."
	density = FALSE
	anchored = TRUE
	/// Set TRUE once a scanner logs its data; the survey objective polls this.
	var/scanned = FALSE

/obj/structure/expedition_survey_beacon/attack_hand(mob/user)
	to_chat(user, span_warning("[src] needs a survey scanner or analyzer to log its readings — your bare hands won't cut it."))

// Scanned with a survey scanner or any handheld analyzer.
/obj/structure/expedition_survey_beacon/attackby(obj/item/W, mob/user)
	if(!istype(W, /obj/item/survey_scanner) && !istype(W, /obj/item/analyzer))
		return ..()
	if(scanned)
		to_chat(user, span_notice("[src] has already been logged."))
		return
	user.visible_message(
		span_notice("[user] sweeps [W] across [src]."),
		span_notice("You begin logging [src]'s readings with [W]...")
	)
	playsound(src, 'sound/items/Deconstruct.ogg', 30, 1)
	if(!do_after(user, 3 SECONDS, target = src))
		return
	if(scanned)
		return
	scanned = TRUE
	to_chat(user, span_notice("Survey data logged to [W]."))

// Handheld survey scanner — exploration department gear (in the explorer kit;
// spares spawn at the launch console).
/obj/item/survey_scanner
	name = "survey scanner"
	desc = "A rugged handheld scanner for logging geological and structural survey markers in the field."
	icon = 'icons/obj/device.dmi'
	icon_state = "atmos"
	w_class = ITEMSIZE_SMALL

// ---------------------------------------------------------------------------
// Extraction beacon: dropped on the site landing pad. Touching it bluespace-
// jumps the user (and anything they're dragging) back to the launch console.
// ---------------------------------------------------------------------------
/obj/structure/expedition_return_beacon
	name = "extraction beacon"
	desc = "A bluespace extraction beacon keyed to the station launch pad. Activate it to return."
	density = FALSE
	anchored = TRUE
	/// The site this beacon belongs to; set when the site is generated.
	var/datum/expedition_site/site

/obj/structure/expedition_return_beacon/attack_hand(mob/user)
	if(!istype(site) || !site.origin_console)
		to_chat(user, span_warning("[src] gives a flat error tone — no return link established."))
		return
	var/turf/dest = site.origin_console.get_return_turf()
	if(!dest)
		to_chat(user, span_warning("[src] cannot find a clear return point on the station pad."))
		return
	user.visible_message(
		span_notice("[user] keys [src] for extraction."),
		span_notice("You key [src] for extraction...")
	)
	if(!do_after(user, 2 SECONDS, src))
		return
	// Pull anything the user is dragging along with them.
	var/atom/movable/pulled = user.pulling
	do_teleport(user, dest, precision = 1, channel = TELEPORT_CHANNEL_BLUESPACE, forced = TRUE)
	if(istype(pulled))
		do_teleport(pulled, dest, precision = 1, channel = TELEPORT_CHANNEL_BLUESPACE, forced = TRUE)
	to_chat(user, span_notice("Bluespace extraction complete. Welcome back."))

/obj/structure/expedition_return_beacon/Destroy()
	site = null
	return ..()

// ---------------------------------------------------------------------------
// Demolition target: a genuinely destructible unstable core. It takes real
// damage from melee, gunfire, mining tools, and explosives via the TG obj_integrity
// model. The "destroy" objective
// polls for its deletion. Tough enough to need real firepower or charges.
// ---------------------------------------------------------------------------
/obj/structure/expedition_demo_target
	name = "unstable reactor core"
	desc = "A dangerously unstable mass of machinery. It needs to come down — bring real firepower or explosives."
	density = TRUE
	anchored = TRUE
	max_integrity = 150

/obj/structure/expedition_demo_target/examine(mob/user)
	. = ..()
	var/perc = get_integrity() / max_integrity
	if(perc > 0.66)
		. += span_warning("Its containment is holding — barely.")
	else if(perc > 0.33)
		. += span_danger("The containment field is failing.")
	else
		. += span_danger("CRITICAL — it's about to rupture!")

// Use the unstable-core glass impact instead of the default structure smash sound.
/obj/structure/expedition_demo_target/play_attack_sound(damage_amount, damage_type = BRUTE, damage_flag = 0)
	playsound(src, 'sound/effects/Glasshit.ogg', 75, 1)

// Reaching 0 integrity ruptures the core.
/obj/structure/expedition_demo_target/atom_destruction(damage_flag)
	visible_message(span_danger("[src] ruptures and collapses in a shower of sparks!"))
	playsound(src, "shatter", 70, 1)
	new /obj/effect/decal/cleanable/ash(get_turf(src))
	return ..()

/obj/structure/expedition_demo_target/attackby(obj/item/W, mob/user)
	if(!istype(W))
		return ..()
	user.setClickCooldown(user.get_attack_speed(W))
	if(W.damtype == BRUTE || W.damtype == BURN)
		user.do_attack_animation(src)
		take_damage(W.force, W.damtype, MELEE)
		return
	return ..()

/obj/structure/expedition_demo_target/bullet_act(obj/item/projectile/Proj)
	var/proj_damage = Proj.get_structure_damage()
	if(!proj_damage)
		return
	..()
	take_damage(proj_damage, Proj.damage_type, BULLET)

/obj/structure/expedition_demo_target/ex_act(severity)
	switch(severity)
		if(1.0)
			take_damage(max_integrity, BRUTE, BOMB)
		if(2.0)
			take_damage(80, BRUTE, BOMB, sound_effect = FALSE)
		if(3.0)
			take_damage(30, BRUTE, BOMB, sound_effect = FALSE)

/obj/structure/expedition_demo_target/attack_generic(mob/user, damage)
	user.setClickCooldown(user.get_attack_speed())
	if(damage >= STRUCTURE_MIN_DAMAGE_THRESHOLD)
		visible_message(span_danger("[user] smashes into [src]!"))
		take_damage(damage, BRUTE, MELEE)
	user.do_attack_animation(src)
	return 1

// ---------------------------------------------------------------------------
// Objective marker: a beacon dropped at a far corner of the site. The "reach"
// objective completes when a crew member gets near it.
// ---------------------------------------------------------------------------
/obj/structure/expedition_marker
	name = "objective marker"
	desc = "A pulsing waypoint beacon marking a point of interest."
	density = FALSE
	anchored = TRUE
