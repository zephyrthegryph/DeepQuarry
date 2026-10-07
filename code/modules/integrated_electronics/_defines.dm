#define IC_INPUT "input"
#define IC_OUTPUT "output"
#define IC_ACTIVATOR "activator"

// Pin functionality.
#define DATA_CHANNEL "data channel"
#define PULSE_CHANNEL "pulse channel"

// Displayed along with the pin name to show what type of pin it is.
#define IC_FORMAT_ANY			"\<ANY\>"
#define IC_FORMAT_STRING		"\<TEXT\>"
#define IC_FORMAT_CHAR			"\<CHAR\>"
#define IC_FORMAT_COLOR			"\<COLOR\>"
#define IC_FORMAT_NUMBER		"\<NUM\>"
#define IC_FORMAT_DIR			"\<DIR\>"
#define IC_FORMAT_BOOLEAN		"\<BOOL\>"
#define IC_FORMAT_REF			"\<REF\>"
#define IC_FORMAT_LIST			"\<LIST\>"

#define IC_FORMAT_PULSE			"\<PULSE\>"

// Used inside input/output list to tell the constructor what pin to make.
#define IC_PINTYPE_ANY				/datum/integrated_io
#define IC_PINTYPE_STRING			/datum/integrated_io/string
#define IC_PINTYPE_CHAR				/datum/integrated_io/char
#define IC_PINTYPE_COLOR			/datum/integrated_io/color
#define IC_PINTYPE_NUMBER			/datum/integrated_io/number
#define IC_PINTYPE_DIR				/datum/integrated_io/dir
#define IC_PINTYPE_BOOLEAN			/datum/integrated_io/boolean
#define IC_PINTYPE_REF				/datum/integrated_io/ref
#define IC_PINTYPE_LIST				/datum/integrated_io/list

#define IC_PINTYPE_PULSE_IN			/datum/integrated_io/activate
#define IC_PINTYPE_PULSE_OUT		/datum/integrated_io/activate/out

// Data limits.
#define IC_MAX_LIST_LENGTH			200

GLOBAL_LIST_INIT(all_integrated_circuits, initialize_integrated_circuits_list())

/proc/initialize_integrated_circuits_list()
	var/list/circuit_list = list()
	for(var/thing in typesof(/obj/item/integrated_circuit))
		circuit_list += new thing()
	return circuit_list

/obj/item/integrated_circuit
	name = "integrated circuit"
	desc = "It's a tiny chip!  This one doesn't seem to do much, however."
	icon = 'icons/obj/integrated_electronics/electronic_components.dmi'
	icon_state = "template"
	w_class = ITEMSIZE_TINY
	var/tmp/obj/item/electronic_assembly/assembly	// Reference to the assembly holding this circuit, if any.
	var/extended_desc = null
	var/list/inputs = list() // ALLOW(instance_list): d: every circuit defines its input pins; setup_io() rebuilds it in place
	var/list/inputs_default			// Assoc list which will fill a pin with data upon creation.  e.g. "2" = 0 will set input pin 2 to equal 0 instead of null.
	var/list/outputs = list() // ALLOW(instance_list): d: every circuit defines its output pins; setup_io() rebuilds it in place
	var/list/outputs_default		// Ditto, for output.
	var/list/activators = list() // ALLOW(instance_list): d: every circuit defines its activator pins; setup_io() rebuilds it in place
	var/next_use = 0 //Uses world.time
	/// Transient: circuits remaining in the current synchronous pulse propagation
	/// budget. Set by check_then_do_work() right before do_work(), read by
	/// activate_pin() to forward downstream. Not meaningful between pulses.
	var/tmp/ic_work_budget = IC_MAX_PULSE_CIRCUITS
	var/complexity = 1 				//This acts as a limitation on building machines, more resource-intensive components cost more 'space'.
	var/size = null					//This acts as a limitation on building machines, bigger components cost more 'space'. -1 for size 0
	var/cooldown_per_use = 1 SECOND // Circuits are limited in how many times they can be work()'d by this variable.
	var/power_draw_per_use = 0 		// How much power is drawn when work()'d.
	var/power_draw_idle = 0			// How much power is drawn when doing nothing.
	var/spawn_flags = null			// Used for world initializing, see the #defines above.
	var/category_text = "NO CATEGORY THIS IS A BUG"	// To show up on circuit printer, and perhaps other places.
	var/removable = TRUE 			// Determines if a circuit is removable from the assembly.
	var/displayed_name = ""
	var/allow_multitool = 1			// Allows additional multitool functionality
									// Used as a global var, (Do not set manually in children).

CAPABILITIES(/obj/item/integrated_circuit)
	owns_many(nameof(inputs))
	owns_many(nameof(outputs))
	owns_many(nameof(activators))
	interface("ICCircuit", state = nameof(GLOB.tgui_physical_state))
	without("ui_open")
	op("rename", ui_act("rename"), then(PROC_REF(ui_act_rename)))
	op("wire", ui_act("wire", arg("link", schema_ref(/datum/integrated_io)), arg("pin", schema_ref(/datum/integrated_io))), then(PROC_REF(ui_act_wire)))
	op("pin_name", ui_act("pin_name", arg("link", schema_ref(/datum/integrated_io)), arg("pin", schema_ref(/datum/integrated_io))), then(PROC_REF(ui_act_wire)))
	op("pin_data", ui_act("pin_data", arg("link", schema_ref(/datum/integrated_io)), arg("pin", schema_ref(/datum/integrated_io))), then(PROC_REF(ui_act_wire)))
	op("pin_unwire", ui_act("pin_unwire", arg("link", schema_ref(/datum/integrated_io)), arg("pin", schema_ref(/datum/integrated_io))), then(PROC_REF(ui_act_wire)))
	op("scan", ui_act("scan"), then(PROC_REF(ui_act_scan)))
	op("examine", ui_act("examine", arg("ref", schema_ref(/obj/item/integrated_circuit))), then(PROC_REF(ui_act_examine)))
	op("remove", ui_act("remove"), then(PROC_REF(ui_act_remove)))
	op("circuit_rename", menu(), label("Rename Circuit"), needs(carried()), then(PROC_REF(circuit_rename_op)))
	on_notice(/datum/notice/hit/emp, then(PROC_REF(circuit_emp_scramble)))

/// Reference to the assembly holding this circuit, if any. (a relation view: null once that is deleted).
/obj/item/integrated_circuit/proc/assembly() as /obj/item/electronic_assembly
	return assembly
