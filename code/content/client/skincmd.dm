/proc/SkinCmd(obj/source, mob/user as mob, data as text)

/proc/SkinCmdRegister(mob/user, name as text, O as obj)
	var/list/cmds = STATE_GET(user, mob_misc, skincmds)
	if(!cmds)
		cmds = list()
		STATE_SET(user, mob_misc, skincmds, cmds)
	cmds[name] = O

/mob/verb/skincmd(data as text)
	set hidden = 1

	var/ref = copytext(data, 1, findtext(data, ";"))
	var/list/cmds = STATE_GET(src, mob_misc, skincmds)
	if (cmds?[ref] != null)
		var/obj/a = cmds[ref]
		SkinCmd(a, src, copytext(data, findtext(data, ";") + 1))
