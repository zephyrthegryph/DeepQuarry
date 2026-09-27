/mob/var/skincmds = list()
/proc/SkinCmd(obj/source, mob/user as mob, data as text)

/proc/SkinCmdRegister(mob/user, name as text, O as obj)
			user.skincmds[name] = O

/mob/verb/skincmd(data as text)
	set hidden = 1

	var/ref = copytext(data, 1, findtext(data, ";"))
	if (src.skincmds[ref] != null)
		var/obj/a = src.skincmds[ref]
		SkinCmd(a, src, copytext(data, findtext(data, ";") + 1))
