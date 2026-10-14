/proc/case_0(list/choices)
    return input("prompt") as text in choices
/proc/case_1(list/choices)
    return input("prompt") as num in choices
/proc/case_2(list/choices)
    return input("prompt") as file in choices
/proc/case_3(list/choices)
    return input("prompt") as icon in choices
/proc/case_4(list/choices)
    return input("prompt") as sound in choices
/proc/case_5(list/choices)
    return input("prompt") as message in choices
/proc/case_6(list/choices)
    return input("prompt") as password in choices
/proc/case_7(list/choices)
    return input("prompt") as color in choices
/proc/case_8(list/choices)
    return input("prompt") as null in choices
/proc/case_9(list/choices)
    return input("prompt") as anything in choices
/proc/case_10(list/choices)
    return input("prompt") as obj in choices
/proc/case_11(list/choices)
    return input("prompt") as obj|text in choices
/proc/case_12(list/choices)
    return input("prompt") as obj|file in choices
/proc/case_13(list/choices)
    return input("prompt") as text|null in choices
/proc/case_14(list/choices)
    return input("prompt") as text|num in choices
/proc/case_15(list/choices)
    return input("prompt") as mob in choices
/proc/case_16(list/choices)
    return input("prompt") as area in choices
/proc/case_17(list/choices)
    return input("prompt") as turf in choices
/proc/omitted(list/choices)
    return input("prompt") in choices
/proc/no_choices()
    return input("prompt") as text
/proc/right_filter(list/choices)
    return input("prompt") as text|obj in choices
/proc/world_choices()
    return input("prompt") as text in world
/proc/usr_choices()
    return input("prompt") as text in usr
/proc/view_choices()
    return input("prompt") as text in view()
/proc/anything_text(list/choices)
    return input("prompt") as text|anything in choices
