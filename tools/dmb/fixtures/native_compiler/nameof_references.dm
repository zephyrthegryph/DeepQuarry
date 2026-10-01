/datum/nameof_member
    var/name
    var/vv_VAS = 4
    proc/reference_names()
        return list(nameof(src.name), nameof(src.vv_VAS), nameof(vv_VAS), nameof(/datum/nameof_member/proc/reference_names))
    proc/static_names()
        var/static/list/names = list(nameof(type::name), nameof(type::vv_VAS))
        return names
/world/New()
    ..()
    var/datum/nameof_member/member = new
    var/list/names = member.reference_names()
    var/list/statics = member.static_names()
    world.log << "NAMEOF_REFS [names.Join(",")] [statics.Join(",")]"
    del(world)
