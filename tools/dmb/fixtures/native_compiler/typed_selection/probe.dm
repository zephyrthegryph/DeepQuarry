/datum/candidate
    var/priority
    New(value)
        priority = value
/proc/select_all()
    var/list/pending = list(new /datum/candidate(2), new /datum/candidate(5), new /datum/candidate(1))
    pending = pending.Copy()
    var/result = 0
    var/iterations = 0
    while(length(pending))
        if(++iterations > 5)
            return -1
        var/datum/candidate/best
        for(var/datum/candidate/C in pending)
            if(!best || C.priority > best.priority)
                best = C
        result = result * 10 + best.priority
        pending -= best
    return result
/world/New()
    world.log << "TYPED_SELECTION [select_all()]"
    del(world)
