/proc/implicit_prompt()
    return input(usr,"message","title",null)
/proc/text_prompt()
    return input(usr,"message","title",null) as text
/proc/implicit_choice(list/choices)
    return input(usr,"message","title",null) in choices
/proc/anything_choice(list/choices)
    return input(usr,"message","title",null) as anything in choices
/proc/implicit_short()
    return input("message")
/proc/text_short()
    return input("message") as text
/proc/implicit_null_choice()
    return input(usr,"message","title",null) in null
/proc/text_null_choice()
    return input(usr,"message","title",null) as text in null
/proc/text_choice(list/choices)
    return input(usr,"message","title",null) as text in choices
