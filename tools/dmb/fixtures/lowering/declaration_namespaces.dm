/datum/declaration_owner
    var
        tmp
            active = 0
            delay = 5
        list
            connected = list()
        height = null
    proc
        declaration_method()
            return list(active, delay, connected, height)
    verb
        declaration_verb()
            return active
/datum/declaration_owner/list
    var/value = 9
proc
    declaration_global()
        return 7
/proc/declaration_values(datum/declaration_owner/o)
    return list(o.active, o.delay, issaved(o.active), issaved(o.connected))
