/proc/dmb_fixture_plain(a)
    return a

/proc/dmb_fixture_typed(a as num, b as text, c as obj)
    return a

/proc/dmb_fixture_in_values(a in list(1, 2, 3))
    return a

/proc/dmb_fixture_in_path(a in /obj)
    return a

/proc/dmb_fixture_defaults(a = 5, b = "hi")
    return a
