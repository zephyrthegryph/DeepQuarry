/datum/probe
    var/charge
    var/excluded
    proc/draw()
        return charge + excluded
    proc/write_values()
        charge=2
        excluded=3
/datum/manual
    var/spare
    var/value
