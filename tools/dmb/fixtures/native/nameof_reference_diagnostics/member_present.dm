/datum/receiver
    var/known
/proc/probe(datum/receiver/R)
    return nameof(R.known)
