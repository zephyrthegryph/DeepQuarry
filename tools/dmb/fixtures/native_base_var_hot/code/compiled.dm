#define TRACKED(T,V)
/atom
    var/one
    var/no_reader
    var/homed
    var/relation
    var/linked
    var/tmp/tmp_one
    var/static/static_one = 0
    var/list/last_default = null
    last_default = list()
TRACKED(/atom, homed)
/datum/other
    var/nonbase
