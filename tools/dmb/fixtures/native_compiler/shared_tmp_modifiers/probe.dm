var/tmp/root_tmp = 1
var/tmp/static/root_shared_tmp = 2
var/tmp/const/root_const_tmp = 3

/datum/tmp_modifiers
    var/tmp/instance_tmp = 4
    var/tmp/static/shared_tmp = 5
    var/tmp/const/constant_tmp = 6

    proc/probe()
        var/tmp/static/proc_static = 7
        return proc_static
