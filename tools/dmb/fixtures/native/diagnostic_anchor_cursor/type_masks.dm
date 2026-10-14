/proc/pure_anything()
    return input("prompt") as anything
/proc/anything_null()
    return input("prompt") as anything|null
/proc/null_anything()
    return input("prompt") as null|anything
/proc/anything_anything()
    return input("prompt") as anything|anything
/proc/text_anything()
    return input("prompt") as text|anything
/proc/anything_text()
    return input("prompt") as anything|text
/proc/obj_anything()
    return input("prompt") as obj|anything
/proc/anything_obj()
    return input("prompt") as anything|obj
/proc/text_null_anything()
    return input("prompt") as text|null|anything
/proc/null_only()
    return input("prompt") as null
/proc/after()
    return 1
