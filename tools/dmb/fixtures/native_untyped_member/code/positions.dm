#define READ_MEMBER(x) x.danger
/datum/static_owner
    var/static/payload
    var/static/ignored_danger
    proc/method()
        return
/proc/member_positions(holder)
    READ_MEMBER(holder)
    for(var/i=0;
        holder.danger;
        i++)
        return
/proc/member_scope(holder)
    (/datum/static_owner::payload).danger
    (/datum/static_owner::method(holder.ignored_danger))
