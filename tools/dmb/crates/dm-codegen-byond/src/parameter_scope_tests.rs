//! Authenticated compiler-only parameter scope controls, captured 516.1687.
use crate::*;

#[test]
fn duplicate_formals_select_last_argument_slot_in_authenticated_native_output() {
    let ast = dm_syntax::parse(include_str!(
        "../../../fixtures/native/parameter_duplicate_diagnostics/duplicate_parameter.dm"
    ));
    let lowered =
        compile_simple_proc_with_params(&ast.items[0].children, &["value".into(), "value".into()])
            .unwrap();
    let linked = link_proc(&lowered.code, &Ledger::default()).unwrap();
    let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../fixtures/native/parameter_duplicate_diagnostics/duplicate_parameter.native.bin"
    ))
    .unwrap();
    let index = native
        .procs
        .iter()
        .position(|proc| native.string(proc.strings[0]) == Some(b"/proc/probe".as_slice()))
        .unwrap();
    assert_eq!(linked.words, native.proc_code_words(index).unwrap());
    assert_eq!(lowered.argument_names, ["value", "value"]);
}

#[test]
fn standalone_parameter_shadow_is_source_error_without_fabricated_header_note() {
    let ast = dm_syntax::parse(include_str!(
        "../../../fixtures/native/parameter_duplicate_diagnostics/local_shadows_parameter.dm"
    ));
    let errors =
        compile_simple_proc_with_params(&ast.items[0].children, &["value".into()]).unwrap_err();
    assert_eq!(errors.len(), 1);
    assert_eq!(errors[0].kind, LowerErrorKind::SourceError);
    assert_eq!(errors[0].reason, "value: duplicate definition");
    assert!(
        errors[0].related.is_empty(),
        "standalone API has no issued signature origin"
    );
}
