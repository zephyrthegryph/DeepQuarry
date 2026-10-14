// Compile-only operand evidence; none of these procedures is executed.
/proc/prompt_omitted()
    return input("message")
/proc/prompt_text()
    return input("message", "title", "default") as text
/proc/prompt_number()
    return input("message", "title", 17) as num
/proc/prompt_message_null()
    return input("message", "title", "default") as message|null
/proc/prompt_text_number_null()
    return input("message", "title", null) as text|num|null
/proc/prompt_icon()
    return input("message", "title", null) as icon
/proc/prompt_file()
    return input("message", "title", null) as file
/proc/prompt_color()
    return input("message", "title", "#abcdef") as color
/proc/prompt_choices(list/choices)
    return input("message", "title", null) in choices
/proc/prompt_anything_choices(list/choices)
    return input("message", "title", null) as anything in choices
/proc/prompt_text_choices(list/choices)
    return input("message", "title", "default") as text in choices
/proc/prompt_null_choices()
    return input("message", "title", null) as text in null
/proc/prompt_mob_null()
    return input("message", "title", null) as mob|null
world
    name = "Compile oracle prompt matrix"
