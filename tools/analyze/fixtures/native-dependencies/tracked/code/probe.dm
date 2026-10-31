#define TRACKED(T,v)
/datum/probe
    var/value
    proc/draw()
        return value
    proc/unrelated()
        return 99
TRACKED(/datum/probe,value)
