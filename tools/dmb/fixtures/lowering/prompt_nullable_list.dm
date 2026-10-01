/proc/prompt_nullable_list(var/user, var/message, var/title, var/default, var/list/options)
    return input(user, message, title, default) as null in options

/proc/prompt_null_only(var/user, var/message, var/title, var/default)
    return input(user, message, title, default) as null
