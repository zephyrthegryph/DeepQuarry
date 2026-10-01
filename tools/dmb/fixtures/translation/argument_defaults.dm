/proc/default_arg_probe(a = 5, b = "hi", c = list(1, 2), d = /obj)
    return a

/proc/default_arg_call()
    return default_arg_probe()

/proc/argument_in_probe(choice as text in list("red", "blue"))
    return choice
