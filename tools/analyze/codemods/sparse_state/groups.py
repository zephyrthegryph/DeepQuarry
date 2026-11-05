#!/usr/bin/env python3
"""The grouping of sparse() slots into lazy owned state datums (doc/rewrite/storage_contract.md): one state per declaring feature.

  python3 tools/analyze/codemods/sparse_state/groups.py            writes groups.tsv next to this file
  python3 tools/analyze/codemods/sparse_state/groups.py --check    fails when groups.tsv is stale

groups.tsv columns: holder, slot, feature, kind, default, wave. `feature` is the owned var on the holder (state type /datum/<feature>_state), the slot is
its field (same name), `default` the value the state var starts as (what every `sparse_get_or(..., default)` gave), `wave` the conversion wave the
slot is in (0 = not converted yet: its holder waits on a decision, or it is a list/weak slot that needs hand work).
"""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from census import census

HERE = os.path.dirname(os.path.abspath(__file__))

# feature -> slots, per holder. Everything not named here goes to the holder's misc feature.
FEATURES = {
    "/mob": {
        "connection": ["lastKnownIP", "computer_id", "disconnect_time", "away_from_keyboard", "manual_afk", "autowhisper_mode", "autowhisper"],
        "spont_belly": ["spont_belly_front", "spont_belly_rear", "spont_belly_left", "spont_belly_right"],
        "motion_track": ["is_motion_tracking", "wants_to_see_motion_echos"],
        "attacker": ["lastattacker_name", "lastattacker_key"],
        "resting_flags": ["dizzy_was_resting", "jittery_was_resting", "lying_prev"],
        "vr_state": ["died_in_vr"],
    },
    "/mob/living": {
        "omen": ["omen_damage", "omen_evil", "omen_incidents", "omen_luck", "omen_safe_disposals", "omen_vorish"],
        "rad_countdown": ["rad_countdown_started", "rad_countdown_minimum"],
        "body_effect": ["body_effect_serial", "body_effect_timers", "body_effect_data"],
        "footfall": ["footstep_vary", "footstep_steps"],
        "slosh": ["slosh_chance", "slosh_steps", "slosh_volume"],
        "trait_injection": ["trait_injection_verb", "trait_injection_reagents", "trait_injection_amount", "trait_injection_selected"],
        "autofire": ["autofire_delay", "autofire_params", "autofire_target"],
        "melee_swing": ["melee_swing_serial", "melee_swing_resolving", "is_swinging"],
        "bodyweight": ["weight", "weight_gain", "weight_loss"],
        "vent_crawl": ["ventcrawl_layer", "is_ventcrawling"],
        "passtable": ["passtable_crawl_checked", "passtable_reset"],
        "capture": ["capture_crystal", "capture_caught"],
        "tm_instability": ["last_instability", "last_instability_event"],
        "gut_disability": ["disability_death_time", "disability_gut_pressure"],
        "breath_hazard": ["failed_last_breath", "air_hazard_at", "air_hazard_breath_at"],
        "vore_fx": ["absorbing_prey", "liquidbelly_visuals", "digestion_in_progress", "prey_controlled", "flight_vore", "vore_egg_type", "stuffing_feeder", "appendage_alt_setting", "drain_finalized", "eggs", "vomiting"],
        "custom_temp": ["custom_heat", "custom_cold"],
    },
    "/mob/living/carbon": {
        "dream_seq": ["dream_wait", "dream_fragments", "current_dream"],
        "posing": ["pose", "pose_move"],
    },
    "/mob/living/carbon/human": {
        "contract_trial": ["contract_medical_indications", "clinical_exposure_history"],
        "regen": ["active_regen", "active_regen_delay"],
        "dq_vitals": ["dq_last_neural_load", "dq_last_radiation", "dq_last_bodytemperature"],
    },
}
MISC = {"/mob": "mob_misc", "/mob/living": "living_misc", "/mob/living/carbon": "carbon_misc", "/mob/living/carbon/human": "human_misc"}
WAVE1 = set(MISC)  # mob-level holders; /atom, /atom/movable, /obj, /obj/item, /obj/machinery wait on the base-type memory decision


def rows():
    out = []
    for v in census():
        h, s = v["holder"], v["slot"]
        feature = None
        for f, slots in FEATURES.get(h, {}).items():
            if s in slots:
                feature = f
        if h in MISC and feature is None:
            feature = MISC[h]
        defaults = list(v["defaults"])
        d = defaults[0] if defaults else ""
        wave = 1 if h in WAVE1 else 0
        if v["kind"] in ("list", "weak") or v["kind"].startswith("/"):
            wave = 0 if v["kind"] in ("list", "weak") else wave
        out.append((h, s, feature or "", v["kind"], d, str(wave)))
    return sorted(out)


def text():
    return "\n".join("\t".join(r) for r in rows()) + "\n"


if __name__ == "__main__":
    path = os.path.join(HERE, "groups.tsv")
    if "--check" in sys.argv:
        sys.exit(0 if open(path, encoding="utf8").read() == text() else "groups.tsv is stale: run groups.py")
    new = text()
    open(path, "w", encoding="utf8", newline="\n").write(new)
    r = rows()
    print(len(r), "slots;", sum(1 for x in r if x[5] == "1"), "in wave 1;", len(set(x[2] for x in r if x[5] == "1")), "features")
