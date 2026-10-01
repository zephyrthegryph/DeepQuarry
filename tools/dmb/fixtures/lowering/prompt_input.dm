/proc/ask_text(var/mob/M)
    return input(M, "Question", "Title", "Default") as text
/proc/ask_num(var/mob/M)
    return input(M, "Q", "T", 3) as num
/proc/ask_choice(var/mob/M)
    return input(M, "Q", "T") in list("a", "b")
