// Occurrences announced with PUBLISH(E, name, field = v): nothing can refuse them, so each is a FIXED ACTION whose notice (the past-tense
// /datum/notice/x of the same name) is generated with the fields below (doc/rewrite/final_api.html sections 8 and 10).

/// From /datum/affliction/proc/set_severity(), sent to the owning mob: (datum/affliction/affliction, old_severity)
ACTION(affliction_severity_changed, affliction, old_severity, FIXED, notice = /datum/notice/affliction_severity_changed)

/// From /datum/body/add_affliction() and remove_affliction(): (datum/affliction/affliction, added)
ACTION(body_afflictions_changed, affliction, added, FIXED, notice = /datum/notice/body_afflictions_changed)

/// From /datum/body/proc/adopt_subtree(), sent to the owning mob once per part that joined it: (obj/item/organ/part)
ACTION(body_part_attached, part, FIXED, notice = /datum/notice/body_part_attached)

/// From /datum/body/proc/release_subtree(), sent to the owning mob once per part that left it: (obj/item/organ/part)
ACTION(body_part_detached, part, FIXED, notice = /datum/notice/body_part_detached)

/// From base of /mob/living/proc/injure(), after the injury applied: (kind, applied, zone, atom/source, flags)
ACTION(living_injured, kind, applied, zone, source_, flags, FIXED, notice = /datum/notice/living_injured)

/// From /mob/living/proc/injure() once mitigation is done, when something listens or the injury trace is on: (incoming_kind, landed_kind, list/stages, zone, atom/source, flags). Each stage is list(INJURY_STAGE_*, amount_in, amount_out, detail).
ACTION(living_injury_explained, incoming_kind, landed_kind, stages, zone, source_, flags, FIXED, notice = /datum/notice/living_injury_explained)

/// From /mob/living/proc/injure(), mitigation stage 2 (energy shields), after armour: (kind, list/amount_ref, zone, atom/source, flags). Shields scale amount_ref[1].
ACTION(living_shield_injury, kind, amount_ref, zone, source_, flags, FIXED, notice = /datum/notice/living_shield_injury)
