/datum/file
/datum/other_file
/datum/message
    var/datum/file/attachment
/datum/other_message
    var/datum/other_file/attachment
/datum/client
    var/datum/message/message
    proc/current_message()
        return message
    proc/check()
        return istype(current_message().attachment)