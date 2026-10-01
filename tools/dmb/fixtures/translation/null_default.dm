/proc/default_arg_plain(mob/target as mob)
/proc/default_arg_null_default(mob/target = null as mob)
/proc/default_arg_text_default(target = null as text)
/proc/default_arg_zero_default(mob/target = 0 as mob)


/proc/choices()
    return list()
/proc/default_arg_list_plain(mob/target as mob in choices())
/proc/default_arg_list_null(mob/target=null as mob in choices())
/proc/default_arg_list_zero(mob/target=0 as mob in choices())

/datum/verb/default_arg_verb_plain(mob/target as mob in choices())
/datum/verb/default_arg_verb_null(mob/target=null as mob in choices())
/datum/verb/default_arg_verb_zero(mob/target=0 as mob in choices())
/datum/verb/default_arg_verb_noin(mob/target=null as mob)
/datum/verb/default_arg_verb_text(target="x" as text)
