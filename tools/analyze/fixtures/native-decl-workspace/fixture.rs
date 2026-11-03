//! Shared physical source only, never native answers or report rows.
pub const CASES:&[&str]=&["basic","allowed","exempt","hidden"];
pub fn files(case:&str)->Vec<(&'static str,Vec<u8>)>{
 let allow=if case=="allowed"{" // ALLOW(decl): retained fixture intentionally models legacy lifecycle construction"}else{""};
 let source=format!("/atom/proc/Initialize()\n    return\n/obj/decl_workspace\n    var/owned\n/obj/decl_workspace/Initialize()\n    after(src, 1, null){allow}\n/obj/decl_workspace/proc/on_destroy()\n    qdel(owned)\n/datum/manual/proc/Initialize()\n    after(src, 1, null)\n/datum/alias\n    parent_type = /obj\n    Initialize()\n        after(src, 1, null)\n");
 let scopes=if case=="exempt"{"[lint.decl]\nexempt_files = [\"code/probe.dm\"]\n"}else{""};
 let mut files=vec![("deepquarry.dme",b"#include \"code/probe.dm\"\n".to_vec()),("code/probe.dm",source.into_bytes()),("code/owned.dm",b"// own_set(src, \"owned\", null)\n".to_vec()),("tools/ci/lint_scopes.toml",scopes.as_bytes().to_vec())];
 if case=="hidden"{files.push(("code/.hidden/probe.dm",b"/obj/hidden/Initialize()\n    after(src, 1, null)\n".to_vec()));}files
}
