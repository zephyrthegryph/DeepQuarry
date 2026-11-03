//! Existing registration/selftest delegates the unique lexical accessor policy.
use crate::{dm::{dx::DxIndex,sys::{register_module,SysModule}},lint::Registry,tree::{SourceFile,Tree}};
use crate::allow_registry_fields::sys_dx_string_names::RULES;
fn selftest() -> Result<String, String> {
    let fixture = [
        r#"own_set(src, "beaker", I)"#,
        "own_set(src, nameof(beaker), I)",
        r#"timed_set(get_holder(x, "a"), "emp", TRUE)"#,
        r#"rel_add(src, "[slot]_link", T)"#,
        "om_set(E, name, value)",
        "/proc/own_set(datum/holder, var_name, datum/value)",
        r#"// own_set(src, "x", I)"#,
        r#"to_chat(user, "own_set(src, \"x\", I)")"#,
        r#"time_left(src, "cooldown")"#,
        r#"own_transfer(src, nameof(a), dest, "b")"#,
        r#"own_transfer(src, nameof(a), dest, nameof(b), member = "x")"#,
    ];
    let f = SourceFile::from_text("x.dm", &fixture.join("\n"));
    let acc = crate::sys_string_names_policy::fallback();
    let pat = crate::sys_string_names_policy::call_pattern(&acc);
    let mut v = Vec::new();
    crate::sys_string_names_policy::scan_lines(&f, &acc, &pat, &mut v);
    let got: Vec<usize> = v.into_iter().map(|(_, n)| n).collect();
    if got != vec![1, 3, 4, 9, 10] {
        return Err(format!("dx_string_names selftest: got {:?}", got));
    }
    // The accessor table is read from the tree's global procs.
    let a = SourceFile::from_text(
        "a.dm",
        "/proc/own_widget(datum/holder, var_name, datum/value)\n\treturn\n/proc/own_key(datum/D)\n\treturn\n/obj/proc/own_set(var_name)\n\treturn\n/proc/om_set(datum/E, name, value)\n\treturn",
    );
    let tree = Tree::from_files(vec![a]);
    let files = vec![tree.get("a.dm").unwrap()];
    let idx = DxIndex::get(&tree, &files);
    let got = crate::sys_string_names_policy::accessors_from(&idx.procs);
    let mut want = crate::sys_string_names_policy::Accessors::new();
    want.insert("own_widget".to_string(), vec![1]);
    want.insert("om_set".to_string(), vec![1]);
    if got != want {
        return Err(format!("dx_string_names selftest: accessors {:?}", got));
    }
    Ok("dx_string_names".to_string())
}

pub fn register(reg: &mut Registry) {
    register_module(
        reg,
        SysModule { name: crate::allow_registry_fields::sys_dx_string_names::SCOPE_MODULE_NAME, rules: RULES, files_scan: Some(crate::sys_string_names_policy::scan), selftest: Some(selftest), py_selftest: true, ..SysModule::DEFAULT },
    );
}
