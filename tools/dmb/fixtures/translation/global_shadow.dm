/proc/definition_first()
    return "good"
/definition_first()
    return "bad"
/override_first()
    return "bad"
/proc/override_first()
    return "good"
/proc/shadow_calls()
    return list(definition_first(),override_first())
