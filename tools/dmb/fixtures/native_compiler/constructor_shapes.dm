/datum/constructor_member
    var/value = 7
var/global/list/constructor_members = newlist(/datum/constructor_member, /datum/constructor_member)
var/global/regex/constructor_regex = new("ab", "i")
var/global/matrix/constructor_matrix = matrix(1, 2, 3, 4, 5, 6)
var/global/image/constructor_image = image(icon_state = "shape", layer = 3)
/datum/constructor_container
    var/list/members = newlist(/datum/constructor_member, /datum/constructor_member)
    var/regex/pattern = new("ab", "i")
    var/matrix/transform = matrix(1, 2, 3, 4, 5, 6)
    var/image/picture = new /image(icon_state = "shape", layer = 3)
/proc/constructor_summary(list/members, regex/pattern, matrix/transform, image/picture)
    var/datum/constructor_member/first = members[1]
    var/datum/constructor_member/second = members[2]
    return "[members.len],[first.value],[second.value],[first != second],[pattern.Find("AB")],[transform.a],[transform.e],[picture.icon_state],[picture.layer]"
/world/New()
    ..()
    world.log << "CONSTRUCTOR_GLOBAL [constructor_summary(constructor_members, constructor_regex, constructor_matrix, constructor_image)]"
    var/datum/constructor_container/container = new
    world.log << "CONSTRUCTOR_CLASS [constructor_summary(container.members, container.pattern, container.transform, container.picture)]"
    del(world)

