/datum/redefinition/plain()
    return 1
/datum/redefinition/allowed()
    return 1
/datum/redefinition/own()
    set SpacemanDMM_can_be_redefined = TRUE
    return 1
/datum/redefinition/rejected()
    set SpacemanDMM_can_be_redefined = FALSE
    return 1
