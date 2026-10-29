/datum/holder
    var/SpacemanDMM_private/saved
    var/SpacemanDMM_private/call_value
    var/SpacemanDMM_private/scalar
    var/SpacemanDMM_private/missing_type/typed
    proc/entity()
        return new /datum
    proc/number()
        return 7
    proc/use(datum/arg)
        saved = arg
        call_value = entity()
        scalar = number()
        typed = arg
