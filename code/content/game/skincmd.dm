/proc/SkinCmd(obj/source, mob/user as mob, data as text)

/proc/SkinCmdRegister(mob/user, name as text, O as obj)
	var/list/cmds = sparse_get(user, skincmds)
	if(!cmds)
		cmds = list()
		sparse_set(user, skincmds, cmds)
	cmds[name] = O

/mob/verb/skincmd(data as text)
	set hidden = 1

	var/ref = copytext(data, 1, findtext(data, ";"))
	var/list/cmds = sparse_get(src, skincmds)
	if (cmds?[ref] != null)
		var/obj/a = cmds[ref]
		SkinCmd(a, src, copytext(data, findtext(data, ";") + 1))
