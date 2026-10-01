/world
/proc/prompt_cond(flag, list/A, list/B)
    return input("title", "message", null) as anything in (flag ? A : B)
/proc/prompt_short(list/A, list/B)
    return input("title", "message", null) as anything in (A || B)
/proc/prompt_nested(flag, list/A, list/B)
    return input("title", "message", null) as anything in (flag ? (A || B) : B)
/proc/prompt_omitted(flag, list/A, list/B)
    return input("title", "message", null) in (flag ? A : B)
/proc/prompt_text(a,b)
    return input(a ? "One" : "Two", b ? "A" : "B", a || "Default") as text
