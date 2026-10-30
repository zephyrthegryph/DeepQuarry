/datum/holder
    var/shallow
    var/deep
    var/implicit
    var/explicit_ignored
    var/range_hit
    var/range_end
    var/init_hit
    var/cond_hit
    var/step_hit
    var/mob/range_shadow
    var/mob/caught_shadow
    proc/check(datum/D, mob/P)
        var/list/datum/L[]
        shallow = L[1]
        deep = L[1][1]
        var/list/sized[implicit = D]
        var/list/suppressed[explicit_ignored = D] = null
        for(var/list/loop[range_hit = D] to (range_end = D))
            break
        for(var/list/cstyle[init_hit = D]; (cond_hit = D); (step_hit = D))
            break
        for(var/datum/range_shadow = 1 to 2)
            range_shadow.key = null
        try
            return
        catch(var/datum/caught_shadow)
            caught_shadow.key = null
        var/static/list/persist[4]
        persist += D
        P.key = null
