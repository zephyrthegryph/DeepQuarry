// Compile-only evidence. No procedure is executed.
/proc/omitted_prompt()
    return input("message")
/proc/omitted_choices(list/choices)
    return input("message") in choices
/proc/file_prompt()
    return input("message") as file
/proc/file_choices(list/choices)
    return input("message") as file in choices
/proc/anything_prompt()
    return input("message") as anything
/proc/anything_choices(list/choices)
    return input("message") as anything in choices
