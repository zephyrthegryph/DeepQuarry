var/list/phase0_preprocess_records = list()
/proc/phase0_preprocess_observe(label, value, expected)
    var/list/record = list("label" = label, "value" = value, "expected" = expected, "matches_expected" = (value == expected))
    phase0_preprocess_records += list(record)
    world.log << "PHASE0 [json_encode(record)]"
/proc/phase0_preprocess_finish()
    text2file(json_encode(phase0_preprocess_records), "phase0-preprocess.json")
    world.log << "PHASE0 DONE"
    del(world)
/proc/phase0_preprocess_value(label, value)
    var/list/record = list("label" = label, "value" = value)
    phase0_preprocess_records += list(record)
    world.log << "PHASE0 [json_encode(record)]"
/proc/phase0_preprocess_global(name)
    if(name in global.vars)
        return global.vars[name]
    return null
