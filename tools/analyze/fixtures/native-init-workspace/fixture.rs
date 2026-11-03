//! Shared authored init sources; no expected native answers.
pub const CASES:&[&str]=&["basic","allowed","exempt","table_order","hidden","roots"];
pub fn files(case:&str)->Vec<(&'static str,Vec<u8>)>{
 let annotation=if case=="allowed"{" // ALLOW(init/INSTANCE_STATE): this actual instance fixture stores state received from construction"}else{""};
 let source=format!("/atom\n    var/init_from_table = FALSE\n/atom/proc/Initialize()\n    return\n/obj/init_workspace/Initialize(){annotation}\n    . = ..()\n    var/state = 1\n    GLOB.value = range(1)\n    return\n/obj/table_parent\n    init_from_table = TRUE\n/obj/table_parent/child/Initialize()\n    return\n/turf/proc/on_materialize()\n    return\n");
 let scope=if case=="exempt"{"[lint.init]\nexempt_files = [\"code/probe.dm\"]\n[lint.init.lists]\ninit_roots = []\n"}else if case=="roots"{"[lint.init]\n[lint.init.lists]\ninit_roots = [\"/obj/init_workspace = real fixture root owns the initialization chain\"]\n"}else{"[lint.init]\n[lint.init.lists]\ninit_roots = []\n"};
 let mut files=vec![("deepquarry.dme",b"#include \"code/probe.dm\"\n".to_vec()),("code/probe.dm",source.into_bytes()),("tools/ci/lint_scopes.toml",scope.as_bytes().to_vec())];
 if case=="table_order"{files.push(("code/z.dm",b"/obj/table_parent\n    init_from_table = TRUE\n".to_vec()));files.push(("code/a_/off.dm",b"/obj/table_parent\n    init_from_table = FALSE\n".to_vec()));}
 if case=="hidden"{files.push(("maps/.hidden/probe.dm",b"/obj/table_parent/hidden/Initialize() // ALLOW(init/CTOR_ARGS): this hidden lifecycle fixture consumes actual construction arguments\n    hidden_state = 1\n".to_vec()));}files
}
