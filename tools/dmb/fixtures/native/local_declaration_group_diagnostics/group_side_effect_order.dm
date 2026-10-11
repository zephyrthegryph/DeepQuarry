/var/step = 0
/proc/next_value()
    step++
    return step
/proc/probe()
    var
        first = next_value(), second = next_value()
        third = first * 100 + second * 10 + next_value()
    return third
