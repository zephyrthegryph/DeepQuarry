#define TRACKED(T,V)
#define READS_FROM(A)
#define READS_AS(P,K)
/datum/probe
    var/value = 1
    var/other = 2
    proc/leaf()
        return value
    proc/method_call()
        return leaf() + other
    proc/global_wrapper()
        return read_probe(src)
    proc/contextual(datum/act/eval/A)
        return A.actor.value + value
    proc/virtual_probe()
        return leaf()
/datum/probe/wide/leaf()
    return other
/datum/act/eval
    var/datum/probe/actor
/proc/read_probe(datum/probe/P)
    READS_FROM(P)
    return P.value
TRACKED(/datum/probe,value)
TRACKED(/datum/probe,other)
