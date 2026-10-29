/proc/untyped()
    return null
/proc/explicit_none()
    set SpacemanDMM_return_type = null
    return null
/proc/probe()
    untyped().plain_unknown
    explicit_none().annotated_none
    new /datum().constructor_unknown
    locate(1,2,3).locate_unknown
    untyped()[1].indexed_unknown
    untyped().outer.inner
