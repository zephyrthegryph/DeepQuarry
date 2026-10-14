// Initialisers that allocate a list per instance, and the ones that do not.
/obj/a
	var/list/l1 = list()
	var/list/l2 = list(1, 2)
	var/list/l3 = alist(1 = 2)
	var/list/l4 = new/list(5)
	var/list/l5 = new /list(5)
	var/list/l6 = new()
	var/list/l7 = new
	var/list/l8[4]
	var/list/l9[SIZE]
	var/list/l10[ SIZE ]
	var/list/typed/path/l11 = list()
	var/list/l12
	var/list/l13 = null
	var/list/l14 = list
	var/list/l15 = list_proc()
	var/list/l16 = newlist()
	var/list/l17 = new /datum/thing()
	var/list/l18 = new()  // trailing comment
	var/list/l19=list()
	var/list/l20 =list()
	var/list/ l21 = list()
	var/ list/l22 = list()
	var/list /l23 = list()
	var/l24 = list()
	var/obj/l25 = list()
	list/l26 = list()
	var/list/l27 = list("a//b", 'c//d.png')
	var/list/l28 = list("esc\"//still a string")
	var/list/l29 = "x" // a "string" in a comment
	var/list/l30 = list() /* block comment */
	var/list/l31 = list(\
		1)
// Modifiers.
/obj/mods
	var/static/list/s1 = list()
	var/global/list/s2 = list()
	var/const/list/s3 = list()
	var/tmp/list/m1 = list()
	var/final/list/m2 = list()
	var/static/tmp/list/s4 = list()
	var/tmp/static/list/s5 = list()
	var/staticky/list/ix = list()
	var/consty/list/iy = list()
	var/globaly/list/iz = list()
/obj/mods/var/staticky/list/dx = list()
/obj/mods/var/static/list/dy = list()
/obj/mods/var/tmp/list/dz = list()
/obj/mods/var/list/dw = list()
/obj/mods/var/list/dv
// Var blocks.
/obj/blocks
	var
		list/b1 = list()
		static/list/b2 = list()
		list/b3
		tmp/list/b4 = list()
		list/b5 = list(1)
	var/static
		list/c1 = list()
		global/list/c2 = list()
		list/c3[4]
	var/tmp
		list/d1 = list()
	var/const
		list/e1 = list()
	var/list/after_block = list()
	var
		list/f1 = list()
	proc/after_proc()
		return
	var/list/g1 = list()
// Procs hide their bodies; a proc at depth 1 ends at its own indent.
/obj/procs
	proc/p1()
		var/list/h1 = list()
		if(1)
			var/list/h2 = list()
	verb/v1()
		var/list/h3 = list()
	p2(a, b)
		var/list/h4 = list()
	var/list/i1 = list()
	proc/p3() as num
		var/list/h5 = list()
	var/list/i2 = list()
/obj/procs/proc/top_level(x)
	var/list/h6 = list()
/obj/procs
	var/list/i3 = list()
/proc/global_proc()
	var/list/h7 = list()
/obj/procs
	var/list/i4 = list()
