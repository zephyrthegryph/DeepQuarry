/datum/base
    var/value = 1800
    var/const/fixed = 7
/datum/base/child
/datum/base/changed
    value = 1900
var/base_value = /datum/base::value
var/child_value = /datum/base/child::value
var/changed_value = /datum/base/changed::value
var/fixed_value = /datum/base::fixed