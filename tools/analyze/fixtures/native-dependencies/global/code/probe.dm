var/global_counter=1
/datum/probe
    proc/draw()
        return global_counter
    proc/write_global()
        global_counter=2
    proc/unrelated()
        return 99
