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
TRACKED(/obj/structure/expedition_survey_beacon, scanned)

MSG_DEF(survey_beacon/logging, span_notice("You begin logging %T%'s readings with %I%..."), span_notice("%U% sweeps %I% across %T%."))
MSG_DEF_SELF(survey_beacon/logged, span_warning("%T% has already been logged."))

CAPABILITIES(/obj/structure/expedition_survey_beacon)
	op("hand", hand(), ungated(), label("Use"), then(PROC_REF(interaction_hand)))
	op("survey_scanner", item(/obj/item/survey_scanner), label("Use"), needs(req(PROC_REF(not_logged))),
		begins(MSG(survey_beacon/logging)), plays(SFX_ITEMS_DECONSTRUCT, at_start = TRUE, volume = 0.6), wait(3 SECONDS), then(PROC_REF(log_readings_done)))
	op("analyzer", item(/obj/item/analyzer), label("Use"), needs(req(PROC_REF(not_logged))),
		begins(MSG(survey_beacon/logging)), plays(SFX_ITEMS_DECONSTRUCT, at_start = TRUE), wait(3 SECONDS), then(PROC_REF(log_readings_done)))

/// Requirement: the marker hasn't been logged yet.
/obj/structure/expedition_survey_beacon/proc/not_logged(datum/act/op/A)
	return (!scanned) ? null : MSG(survey_beacon/logged)

/// Old attack_hand.
/obj/structure/expedition_survey_beacon/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_warning("[src] needs a survey scanner or analyzer to log its readings — your bare hands won't cut it."))
	return TRUE

// Scanned with a survey scanner or any handheld analyzer.
/obj/structure/expedition_survey_beacon/proc/log_readings_done(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(scanned)
		return
	set_scanned(TRUE)
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
	play_sfx(src, SFX_EFFECTS_GLASSHIT)

// Reaching 0 integrity ruptures the core.
/obj/structure/expedition_demo_target/atom_destruction(damage_flag)
	visible_message(span_danger("[src] ruptures and collapses in a shower of sparks!"))
	play_sfx(src, SFX_SHATTER)
	new /obj/effect/decal/cleanable/ash(get_turf(src))
	return ..()

/// Old attackby.
/obj/structure/expedition_demo_target/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(!istype(W))
		return OP_DECLINE
	user.setClickCooldown(user.get_attack_speed(W))
	if(W.obj_damage_type())
		user.do_attack_animation(src)
		receive_weapon_hit(W, user, silent = FALSE)
		return OP_PASS
	return OP_DECLINE

CAPABILITIES(/obj/structure/expedition_demo_target)
	extend(/datum/act/hit/generic, instead(then(PROC_REF(smashed_by))))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

/// A simple mob's (or a xeno's) generic hit on it, taken over (the hit/generic action): HOOK_DECLINE lets the default generic attack land.
/obj/structure/expedition_demo_target/proc/smashed_by(datum/act/hit/generic/A)
	var/mob/user = A.attacker
	var/damage = A.damage
	user.setClickCooldown(user.get_attack_speed())
	if(damage >= STRUCTURE_MIN_DAMAGE_THRESHOLD)
		act_message(user, src, others = span_danger("%U% smashes into %T%!"))
		receive_generic_attack(user, damage)
	user.do_attack_animation(src)
	return OP_OK

// ---------------------------------------------------------------------------
// Objective marker: a beacon dropped at a far corner of the site. The "reach"
// objective completes when a crew member gets near it.
// ---------------------------------------------------------------------------
/obj/structure/expedition_marker
	name = "objective marker"
	desc = "A pulsing waypoint beacon marking a point of interest."
	density = FALSE
	anchored = TRUE
