/proc/short_assignment_or(list/a, list/b)
    a[1] ||= b[1]
    return a[1] * 10 + b[1]
/proc/short_assignment_and(list/a, list/b)
    a[1] &&= b[1]
    return a[1] * 10 + b[1]
/proc/short_assignment_expression(list/a, list/b)
    var/result = (a[1] ||= b[1])
    return result * 100 + a[1] * 10 + b[1]
/world/New()
    ..()
    world.log << "SHORT_ASSIGN [short_assignment_or(list(0),list(7))] [short_assignment_and(list(2),list(7))] [short_assignment_expression(list(0),list(7))]"
    var/datum/assignment_holder/a = new
    var/datum/assignment_holder/b = new
    b.value = 7
    var/member_result = short_assignment_member(a,b)
    var/index_result = short_assignment_index_effects(list(0,0),list(6,7),list(0))
    world.log << "SHORT_ASSIGN_COMPLEX [member_result] [index_result]"
    del(world)

/datum/assignment_holder
    var/value = 0
/proc/assignment_receiver(datum/assignment_holder/holder)
    return holder
/proc/short_assignment_member(datum/assignment_holder/a, datum/assignment_holder/b)
    assignment_receiver(a).value ||= assignment_receiver(b).value
    return a.value * 10 + b.value
/proc/assignment_index(list/count)
    count[1] += 1
    return count[1]
/proc/short_assignment_index_effects(list/a, list/b, list/count)
    a[assignment_index(count)] ||= b[assignment_index(count)]
    return a[1] * 100 + b[2] * 10 + count[1]
