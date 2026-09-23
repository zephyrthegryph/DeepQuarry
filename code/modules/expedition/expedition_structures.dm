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
	if(W.obj_damage_type())
		user.do_attack_animation(src)
		receive_weapon_hit(W, user, silent = FALSE)
		return
	return ..()

/obj/structure/expedition_demo_target/ex_act(severity)
	switch(severity)
		if(1.0)
			deal_damage(DAMAGE_BLAST, max_integrity)
		if(2.0)
			deal_damage(DAMAGE_BLAST, 80, flags = DAMAGE_PACKET_SILENT)
		if(3.0)
			deal_damage(DAMAGE_BLAST, 30, flags = DAMAGE_PACKET_SILENT)

/obj/structure/expedition_demo_target/attack_generic(mob/user, damage)
	user.setClickCooldown(user.get_attack_speed())
	if(damage >= STRUCTURE_MIN_DAMAGE_THRESHOLD)
		visible_message(span_danger("[user] smashes into [src]!"))
		receive_generic_attack(user, damage)
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
