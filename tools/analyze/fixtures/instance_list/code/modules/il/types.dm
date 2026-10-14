/obj/braced {
	var/list/t1 = list()
}
/obj/commented // a comment on the type line
	var/list/t2 = list()
/obj/proc/withparens(x)
	var/list/hidden = list()
/obj/after_proc
	var/list/t3 = list()
var/list/global_list = list()
/var/list/global_list2 = list()
/obj/sp1
 var/list/spaced1 = list()
  /obj/spaced_type
	var/list/t4 = list()
	var/list/t4b = list()
/obj/tabbed
	var/list/t5 = list()
		var/list/t6 = list()
/obj/nested/var/list/n1 = list()
/obj/nested/var/list/n2 // no initialiser
/datum/thing/var/list/n3 = new /list(3)
/datum/thing/var/list/n4 = list()  // a trailing comment
/datum/thing/var/static/list/n5 = list()
/datum/thing/var/list
	// an odd declaration with nothing on the line
/datum
	var/list/bare_datum = list()
/obj/wide/type/path/that/goes/deep
	var/list/t7 = list()
/obj/a
	var/list/dup_in_file = list()
/obj/a
	var/list/dup_in_file = list()
/obj/x/y
	var/list/z = list()
/obj/x
	var/list/y_z = list()
/obj/depth0/var/list/z0[4]
/obj/depth0/var/list/z1 = new
/obj/depth0/var/staticky/list/z2 = new
/obj/depth0/var/static/list/z3 = new
/obj/depth0/var/tmp/list/z4 = new
/obj/depth0/var/list/z5 = list()
