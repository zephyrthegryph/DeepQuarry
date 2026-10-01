/datum/ref_owner/proc/check()
    return 1
/datum/ref_owner/check()
    return 2
/proc/definition_reference()
    return /datum/ref_owner/proc/check
/proc/override_reference()
    return /datum/ref_owner/check
/world/Error()
    return 9
/proc/callback_reference()
    return /world/Error
/var/list/force516=alist()
/proc/root_probe()
    return 1
/root_probe()
    return 2
/proc/ignored_root_reference()
    return /root_probe
/proc/named_root_call()
    return root_probe()
/mob/Login()
    return 11
/client/Topic()
    return 12
/datum/Read()
    return 13
/proc/mob_callback_reference()
    return /mob/Login
/proc/client_callback_reference()
    return /client/Topic
/proc/datum_callback_reference()
    return /datum/Read