//! Builtins and diagnostics lowering regression tests.
use super::*;

#[test]
fn istype_usr_matches_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/istype_usr/probe.dm"
    ));
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/istype_usr/probe.native.bin"
    ))
    .unwrap();
    let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
    let mut ledger = Ledger::default();
    ledger
        .bind(crate::Symbol::new(Table::Class, "/mob"), 0)
        .unwrap();
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    assert_eq!(linked.words, native.proc_code_words(0).unwrap());
}

#[test]
fn predefined_exception_and_regex_macro_expansions_match_native() {
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/native_compiler/predefined_macros.native.bin"
    ))
    .unwrap();
    let words = native.proc_code_words(0).unwrap();
    let file = std::str::from_utf8(&native.strings[words[8] as usize].data).unwrap();
    let source=format!("/proc/e(message)\n    return new /exception(message, {}, 2)\n/proc/r(message)\n    return regex(message,1)\n/proc/rr(message)\n    return regex(message,2)\n",serde_json::to_string(file).unwrap());
    let ast = dm_syntax::parse(&source);
    for (index, item) in ast.items.iter().enumerate() {
        let compiled =
            compile_simple_proc_with_params(&item.children, &["message".into()]).unwrap();
        let mut ledger = Ledger::default();
        ledger
            .bind(crate::Symbol::new(Table::Class, "/exception"), words[2])
            .unwrap();
        for key in &compiled.strings {
            let id = native
                .strings
                .iter()
                .position(|s| s.data == compiled.string_bytes(key))
                .unwrap();
            ledger
                .bind(crate::Symbol::new(Table::String, key), id as u32)
                .unwrap();
        }
        assert_eq!(
            link_proc(&compiled.code, &ledger).unwrap().words,
            native.proc_code_words(index).unwrap(),
            "proc {index}"
        );
    }
}

#[test]
fn gradient_and_resource_output_forms_match_native() {
    for (source, bytes) in [
        (
            include_str!("../../../../../fixtures/native_compiler/gradient_output.dm"),
            include_bytes!("../../../../../fixtures/native_compiler/gradient_output.native.bin")
                .as_slice(),
        ),
        (
            include_str!("../../../../../fixtures/native_compiler/addtext_link.dm"),
            include_bytes!("../../../../../fixtures/native_compiler/addtext_link.native.bin")
                .as_slice(),
        ),
    ] {
        let ast = dm_syntax::parse(source);
        let native = byond_dmb::dmb::Dmb::from_bytes(bytes).unwrap();
        for (index, item) in ast.items.iter().enumerate() {
            let header = &item.header;
            let params = header
                .split_once('(')
                .unwrap()
                .1
                .trim_end_matches(')')
                .split(',')
                .map(|s| s.trim().to_owned())
                .collect::<Vec<_>>();
            let compiled = compile_simple_proc_with_params(&item.children, &params).unwrap();
            let mut ledger = Ledger::default();
            for key in &compiled.strings {
                let id = native
                    .strings
                    .iter()
                    .position(|s| s.data == compiled.string_bytes(key))
                    .unwrap();
                ledger
                    .bind(crate::Symbol::new(Table::String, key), id as u32)
                    .unwrap();
            }
            assert_eq!(
                link_proc(&compiled.code, &ledger).unwrap().words,
                native.proc_code_words(index).unwrap(),
                "{}",
                item.header
            );
        }
    }
}

#[test]
fn stat_panels_and_missile_statements_match_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/native_compiler/stat_special.dm"
    ));
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/native_compiler/stat_special.native.bin"
    ))
    .unwrap();
    for (index, item) in ast.items.iter().enumerate() {
        let params = match index {
            0 | 3 => vec!["a".into(), "b".into()],
            1 | 2 => vec!["a".into()],
            _ => vec!["a".into(), "b".into(), "c".into()],
        };
        let compiled = compile_simple_proc_with_params(&item.children, &params).unwrap();
        assert_eq!(
            link_proc(&compiled.code, &Ledger::default()).unwrap().words,
            native.proc_code_words(index).unwrap(),
            "proc {index}"
        );
    }
}

#[test]
fn savefile_read_evaluates_complex_destinations_after_reading() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/native_compiler/input_complex.dm"
    ));
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/native_compiler/input_complex.native.bin"
    ))
    .unwrap();
    for (name, id, params) in [
        ("/proc/read_index", 6, vec!["S".into(), "L".into()]),
        ("/proc/read_dynamic_field", 8, vec!["S".into()]),
    ] {
        let item = ast
            .items
            .iter()
            .find(|item| item.header.starts_with(name))
            .unwrap();
        let bindings = LowerBindings {
            parameters: params,
            global_procs: BTreeSet::from(["get_holder".into()]),
            ..LowerBindings::default()
        };
        let compiled = compile_simple_proc_with_bindings(&item.children, &bindings).unwrap();
        let mut ledger = Ledger::default();
        for key in &compiled.strings {
            let id = native
                .strings
                .iter()
                .position(|s| s.data == compiled.string_bytes(key))
                .unwrap();
            ledger
                .bind(crate::Symbol::new(Table::String, key), id as u32)
                .unwrap();
        }
        ledger
            .bind(crate::Symbol::new(Table::Proc, "/proc/get_holder"), 7)
            .unwrap();
        assert_eq!(
            link_proc(&compiled.code, &ledger).unwrap().words,
            native.proc_code_words(id).unwrap(),
            "{name}"
        );
    }
}

#[test]
fn output_statements_and_special_forms_match_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/native_compiler/output_special.dm"
    ));
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/native_compiler/output_special.native.bin"
    ))
    .unwrap();
    for (index, item) in ast.items.iter().enumerate() {
        let params = if matches!(index, 2..=5) {
            vec![
                "target".into(),
                "value".into(),
                if index == 2 {
                    "options"
                } else if index == 5 {
                    "control"
                } else {
                    "name"
                }
                .into(),
            ]
        } else {
            vec!["target".into(), "value".into()]
        };
        let compiled = compile_simple_proc_with_params(&item.children, &params).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        assert_eq!(
            linked.words,
            native.proc_code_words(index).unwrap(),
            "proc {index}"
        );
    }
}

#[test]
fn crash_vector_and_variadic_text_comparisons_match_native() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/native_compiler/special_builtins.dm"
    ));
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/native_compiler/special_builtins.native.bin"
    ))
    .unwrap();
    let parameters = [
        vec!["value"],
        vec![],
        vec!["a", "b"],
        vec!["a", "b", "c"],
        vec!["a", "b", "c"],
        vec![],
        vec!["a", "b", "c"],
    ];
    for (index, names) in parameters.iter().enumerate() {
        let params = names
            .iter()
            .map(|name| (*name).to_owned())
            .collect::<Vec<_>>();
        let compiled =
            compile_simple_proc_with_params(&ast.items[index].children, &params).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        assert_eq!(
            linked.words,
            native.proc_code_words(index).unwrap(),
            "proc {index}"
        );
    }
}

#[test]
fn proc_path_literal_uses_proc_table_value_tag() {
    let ast = dm_syntax::parse(include_str!(
        "../../../../../fixtures/translation/proc_path_literal/probe.dm"
    ));
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let compiled = compile_simple_proc(&ast.items[1].children).unwrap();
    let mut ledger = Ledger::default();
    ledger
        .bind(crate::Symbol::new(Table::Proc, "/proc/foo"), 0)
        .unwrap();
    let linked = link_proc(&compiled.code, &ledger).unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/translation/proc_path_literal/probe.native.bin"
    ))
    .unwrap();
    assert_eq!(linked.words, native.proc_code_words(1).unwrap());
}

#[test]
fn unsupported_control_flow_fails_closed() {
    let ast = dm_syntax::parse("/proc/test()\n  switch(1)\n    return 2\n");
    assert!(compile_simple_proc(&ast.items[0].children).is_err());
}

#[test]
fn else_if_chain_has_valid_targets() {
    let ast = dm_syntax::parse("/proc/test(x)\n  if(x == 1)\n    return 10\n  else if(x == 2)\n    return 20\n  else\n    return 30\n");
    let compiled = compile_simple_proc_with_params(&ast.items[0].children, &["x".into()]).unwrap();
    let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
    let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
    let starts: BTreeSet<_> = decoded
        .iter()
        .map(|instruction| instruction.offset as u32)
        .collect();
    for instruction in decoded {
        for target in instruction.branch_targets().unwrap() {
            assert!(starts.contains(&target));
        }
    }
}

#[test]
fn native_simple_fixture_matches_compiled_bodies() {
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/native_compiler/simple.native.bin"
    ))
    .unwrap();
    let names: Vec<_> = native
        .procs
        .iter()
        .enumerate()
        .filter_map(|(id, proc)| {
            let name = String::from_utf8_lossy(native.string(proc.strings[0])?).into_owned();
            name.contains("return_").then(|| {
                (
                    name,
                    id,
                    native.proc_code_words(id).unwrap_or_default().to_vec(),
                )
            })
        })
        .collect();
    assert_eq!(names.len(), 3);
    let source = dm_syntax::parse(include_str!(
        "../../../../../fixtures/native_compiler/simple.dm"
    ));
    for (item, (name, _, expected)) in source.items.iter().zip(&names) {
        let compiled = compile_simple_proc(&item.children).unwrap();
        let mut ledger = Ledger::default();
        for string in &compiled.strings {
            let id = native
                .strings
                .iter()
                .position(|entry| entry.data == string.as_bytes())
                .unwrap() as u32;
            ledger
                .bind(crate::Symbol::new(Table::String, string), id)
                .unwrap();
        }
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        assert_eq!(&linked.words, expected, "{name}");
    }
}

#[test]
fn native_flow_fixture_matches_compiled_bodies_and_metadata() {
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/native_compiler/flow.native.bin"
    ))
    .unwrap();
    let source = dm_syntax::parse(include_str!(
        "../../../../../fixtures/native_compiler/flow.dm"
    ));
    for item in &source.items {
        let name = item.header.split('(').next().unwrap();
        let id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(name.as_bytes()))
            .unwrap();
        let native_proc = &native.procs[id];
        let compiled = compile_simple_proc_with_params(&item.children, &["x".into()]).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        assert_eq!(linked.words, native.proc_code_words(id).unwrap(), "{name}");
        let local_words = &native.lists[native_proc.code_locals_args[1] as usize];
        let expected_local_names = local_words
            .iter()
            .map(|id| {
                let variable = &native.variables[*id as usize];
                String::from_utf8_lossy(native.string(variable.name).unwrap()).into_owned()
            })
            .collect::<Vec<_>>();
        assert_eq!(compiled.local_names, expected_local_names, "{name} locals");
        let expected_args = native.proc_arguments(id).unwrap();
        let arguments = compiled.argument_metadata();
        assert_eq!(arguments.len(), expected_args.len());
        for (actual, expected) in arguments.iter().zip(expected_args) {
            assert_eq!(
                (actual.type_flags, actual.value_source, actual.reserved),
                (
                    expected.type_flags,
                    expected.value_source,
                    expected.reserved
                )
            );
            assert_eq!(
                native.string(native.variables[expected.variable_id as usize].name),
                Some(actual.name.as_bytes())
            );
        }
    }
}
