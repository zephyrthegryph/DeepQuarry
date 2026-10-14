/datum/receiver/proc/known()
    return 1
/proc/probe(datum/receiver/R)
    return nameof(R.known)
