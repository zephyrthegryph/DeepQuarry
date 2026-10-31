#define CAPABILITIES(T, entries...)
#define CAP_ENTRIES(T, entries...)
#define STAT(T, name, rule, args...)
#define TRACKED(T,V)
#define REL(T,V)
#define READS_AS(proc,key,args...)
#define MOB_KEY_READER "reader"
#define TRUE 1
#define FALSE 0
/datum/act
/datum/look
/obj/item/cell
	var/charge = 10
/obj/probe
	var/charge = 1
	var/other = 2
	var/obj/item/cell/cell
TRACKED(/obj/probe, charge)
REL(/obj/probe, cell)
CAPABILITIES(/obj/probe, on_change(nameof(reader_only), then(PROC_REF(refresh))), contributes(STAT_POWER, nameof(stat_input)))
STAT(/obj/probe, power, ADD)
/obj/probe/proc/draw(datum/look/L)
	return charge + cell.charge
/obj/probe/proc/hidden_verbs()
	return charge
/obj/probe/proc/granted_verbs()
	return vars["other"]
/obj/probe/proc/reactions()
	return on_change("terminal.power", then(PROC_REF(refresh)))
/obj/probe/proc/generated_reads()
	return list(nameof(charge))
/obj/probe/proc/derived()
	return derives(nameof(other), PROC_REF(compute))
/obj/probe/proc/refresh()
	return charge
/datum/capability/powered/proc/draw(holder, look)
	return holder
/proc/entries_helper()
	return on_change(nameof(helper_read), then(PROC_REF(refresh)))
