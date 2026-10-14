var/list/phase0_records = list()
/proc/phase0_emit(label, value)
    var/list/record = list("label" = label, "value" = value)
    phase0_records += list(record)
    world.log << "PHASE0 [json_encode(record)]"
/proc/phase0_finish()
    text2file(json_encode(phase0_records), "phase0-link.json")
    world.log << "PHASE0 DONE"
    del(world)
