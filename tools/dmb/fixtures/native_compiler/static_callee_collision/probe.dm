/proc/colliding(value)
    return value + 1
/proc/static_constructors()
    var/static/regex/regex = regex(@"a+", "g")
    var/static/list/colliding = list(1)
    var/static/result = colliding(5)
    return regex.Find("aaa") + result
