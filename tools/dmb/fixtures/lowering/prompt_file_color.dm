/proc/prompt_file(var/user, var/message, var/title, var/default)
    return input(user, message, title, default) as null|file

/proc/prompt_file_required(var/user, var/message, var/title, var/default)
    return input(user, message, title, default) as file

/proc/prompt_number_nullable(var/user, var/message, var/title, var/default)
    return input(user, message, title, default) as null|num

/proc/prompt_color(var/user, var/message, var/title, var/default)
    return input(user, message, title, default) as null|color

/proc/prompt_computed(var/user, var/message, var/title, var/default)
    return input(user, uppertext(message), title, default) as null|text

/proc/prompt_computed_selection(var/user, var/message, var/title, var/default, var/list/groups)
    return input(user, message, title, default) as null in groups[1]

/proc/prompt_mob_selection(var/user, var/message, var/title, var/default, var/list/options)
    return input(user, message, title, default) as mob in options
