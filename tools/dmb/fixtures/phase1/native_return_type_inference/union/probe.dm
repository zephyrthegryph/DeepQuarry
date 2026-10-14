/datum/file
/datum/message
    var/datum/file/attachment
/datum/client
    var/datum/message/message
    proc/current_message() as /datum/message|/datum/file
        return message
    proc/check()
        return istype(current_message().attachment)