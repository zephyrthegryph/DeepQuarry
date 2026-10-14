// Standalone historical damage threshold algorithm, not game rule lifecycle.
#define DAMAGE_BAND_NONE 0
#define DAMAGE_BAND_LIGHT 1
#define DAMAGE_BAND_MODERATE 2
#define DAMAGE_BAND_HEAVY 3

/datum/threshold
    var/value
    var/band

/proc/damage_band_at(ratio, list/rules)
    . = DAMAGE_BAND_NONE
    for(var/datum/threshold/rule as anything in rules)
        if(ratio < rule.value && rule.band > .)
            . = rule.band

/proc/check_threshold(label, ratio, expected, list/rules)
    var/integrity = ratio * 200
    var/reconstructed = integrity / 200
    var/band = damage_band_at(reconstructed, rules)
    var/maximum = DAMAGE_BAND_NONE
    for(var/datum/threshold/rule as anything in rules)
        if(reconstructed < rule.value)
            maximum = max(maximum, rule.band)
    world.log << "DQ_DAMAGE [label] [band] [maximum] [expected] [band == expected && maximum == expected]"

/world/New()
    ..()
    var/datum/threshold/light = new
    light.value = 0.75
    light.band = DAMAGE_BAND_LIGHT
    var/datum/threshold/moderate = new
    moderate.value = 0.5
    moderate.band = DAMAGE_BAND_MODERATE
    var/datum/threshold/heavy = new
    heavy.value = 0.25
    heavy.band = DAMAGE_BAND_HEAVY
    var/list/rules = list(light, moderate, heavy)
    check_threshold("full", 1, DAMAGE_BAND_NONE, rules)
    check_threshold("light", 0.7, DAMAGE_BAND_LIGHT, rules)
    check_threshold("moderate", 0.45, DAMAGE_BAND_MODERATE, rules)
    check_threshold("heavy", 0.2, DAMAGE_BAND_HEAVY, rules)
    check_threshold("repair_light", 0.6, DAMAGE_BAND_LIGHT, rules)
    check_threshold("repair_full", 0.9, DAMAGE_BAND_NONE, rules)
    check_threshold("heavy_again", 0.1, DAMAGE_BAND_HEAVY, rules)
    check_threshold("boundary_light", 0.75, DAMAGE_BAND_NONE, rules)
    check_threshold("boundary_moderate", 0.5, DAMAGE_BAND_LIGHT, rules)
    check_threshold("boundary_heavy", 0.25, DAMAGE_BAND_MODERATE, rules)
    world.log << "DQ_DAMAGE finished"
    shutdown()
