_om_start()
x = _om_foo_bar(1)
x._om_thing()
a_om_b()
__om_x()
/proc/_om_def()
// _om_commented()
x = "_om_in_string"
_om_one() _om_two()
_om_allowed() // ALLOW(om_internal): scheduler boot
// ALLOW(om_internal): above
_om_allowed_above()
// ALLOW(other): wrong
_om_wrong_name()
_om_a() /* ALLOW(om_internal): block form */
	// ALLOW(om_internal)
_om_no_reason()
_om_
x = (_om_paren)
-_om_neg
	_om_ok() // ALLOW(om_internal, other): both
om_after()
x_om_y
