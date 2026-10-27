/datum/notice/asked
	read_back = TRUE
	var/lines

/datum/notice/asked/sub

/datum/notice/plain
	var/lines

/datum/fx/proc/on_asked(datum/act/notice/A)
	var/datum/notice/asked/event = A
	event.lines += "ok"

/datum/fx/proc/on_sub(datum/notice/asked/sub/N)
	var/list/l = N.lines
	l += "ok"

/datum/fx/proc/on_plain(datum/act/notice/A)
	var/datum/notice/plain/event = A
	event.lines += "bad"

/datum/fx/proc/on_plain_alias(datum/notice/plain/N)
	var/list/l = N.lines
	l[1] = "bad"

/datum/fx/proc/sender()
	var/datum/notice/plain/N = notice_take(/datum/notice/plain)
	N.lines = list()

/datum/notice/plain/fill(lines)
	src.lines = lines
