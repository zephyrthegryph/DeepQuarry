/datum/thing
	var/list/a = list()
	var/list/b = list() // trailing comment
	var/list/c = list() /* block */
	var/list/d = list( )
	var/list/e = list(1, 2)
	var/list/f = list() + list()
	var/list/g = list()  // ALLOW(instance_list): a real fixture reason for this declaration
	// ALLOW(instance_list): a real fixture reason from the comment line above
	var/list/h = list()
	var/list/i = list() // ALLOW(base_vars): the base_vars name keeps a list_init site too
	var/list/j = list() // ALLOW(instance_list)
	var/static/list/k = list()
	var/const/list/l = list()
	var/global/list/m = list()
	var/tmp/list/n = list()
	var/o = list()
	var/s = "a = list() // quoted"
	var/t = "a = list()"
	var/list/u
	var/list/v = null
	var/list/w =list()
	var/list/x=list()
	var/list/y = list()
	var/list/z = list()	// tab then comment
	var/list/ml = list(
		1,
		2)
	var/list/after_ml = list()
/datum/thing/sub
	var
		list/blk_a = list()
		static/list/blk_b = list()
		list/blk_c = list(1)
	var/tmp
		list/blk_d = list()
/datum
	var/list/bare_datum = list()
/datum/other
	var/list/a = list()
