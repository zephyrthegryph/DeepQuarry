var/list/OPTIONS = list("x")
/proc/global_options(a in OPTIONS)
    return a
/proc/member_options(mob/m, a in m.contents)
    return a
/proc/choices(atom_target)
    return list(atom_target)
/proc/call_options(atom_target, choice in choices(atom_target))
    return choice
/proc/unused_options(unused, atom_target, choice in choices(atom_target))
    return choice
