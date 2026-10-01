/datum/probe_save
    var/saved_var = 1
    var/tmp/unsaved_var = 2
/proc/alert_one(mob/M)
    return alert(M)
/proc/alert_two(mob/M)
    return alert(M, "Message")
/proc/alert_four(mob/M)
    return alert(M, "Message", "Title", "Yes")
/proc/alert_six(mob/M)
    return alert(M, "Message", "Title", "Yes", "No", "Cancel")
/proc/alert_omitted(mob/M)
    return alert(M, "Message",, "Yes", "No")
/proc/issaved_member(datum/probe_save/D)
    return issaved(D.saved_var)
/proc/issaved_index(datum/probe_save/D)
    return issaved(D.vars["saved_var"])
