/datum/box
    var/specific
    var/wild
    var/ctor_only
    var/shadow
/datum/box/child
/datum/unrelated
    var/specific
/datum/box/New()
    ctor_only = 1
/datum/box/proc/write_typed(datum/box/child/B)
    B.specific += 1
/datum/box/proc/write_unknown(B)
    B.wild++
/datum/box/proc/local_shadow()
    var/shadow
    shadow = 1
/datum/unrelated/proc/read_only()
    return specific
/datum/singleton
    var/list/booted
    var/list/dynamic
/datum/singleton/proc/fill()
    booted = list()
/datum/singleton/proc/poke()
    dynamic.Add(1)
/datum/system/boot/proc/initialize_more()
    var/datum/singleton/S
    S.fill()
/datum/global_owner_control
    proc/missing_field_is_not_global()
        var/datum/global_owner_control/P=src
        P.global_only_control=1

/datum/auto_case
    var/self_only
    var/other_var
    var/changed
    var/ctor_only
    var/generated_only
    proc/set_self_only(v)
        self_only=v
    proc/set_other_var(v)
        other_var=v
        changed=v
    New()
        ctor_only=1
    var/list/list_free
    var/list/list_blocked
    var/list/list_version_taken
    var/list_version_taken_version
    var/static/static_x
    var/const/const_x=1
    var/excluded_x
    proc/add_list_blocked(x)
        return
