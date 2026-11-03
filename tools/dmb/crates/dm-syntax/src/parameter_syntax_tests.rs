use super::*;
fn signature(source: &str) -> crate::ProcedureParameters {
    crate::parse_proc_with_origins_at_span(source, Span::new(0, source.len()))
        .unwrap()
        .parameters
}
#[test]
fn primary_parameter_receipt_strips_only_old_leading_modifiers() {
    let source="/proc/p(var/static/const/datum/A, datum/static/B, SpacemanDMM_private/SpacemanDMM_protected/datum/C, final/D)\n    return\n";
    let signature = signature(source);
    let rows = signature.entries().unwrap();
    assert_eq!(
        rows.iter()
            .map(|p| p.source_modifiers())
            .collect::<Vec<_>>(),
        [5, 0, 96, 16]
    );
    assert_eq!(
        rows.iter()
            .map(|p| p.type_path(source).unwrap())
            .collect::<Vec<_>>(),
        [
            Some("/datum".into()),
            Some("/datum/static".into()),
            Some("/datum".into()),
            None
        ]
    );
    assert_eq!(
        rows.iter()
            .map(|p| &source[p.name().range()])
            .collect::<Vec<_>>(),
        ["A", "B", "C", "D"]
    );
}
#[test]
fn primary_parameter_suffix_adds_one_list_without_reparsing_dimensions() {
    let source = "/proc/p(datum/D[2][length(list(1,2))], list/datum/L[], tmp/X[])\n    return\n";
    let signature = signature(source);
    let rows = signature.entries().unwrap();
    assert_eq!(
        rows.iter()
            .map(|p| p.type_path(source).unwrap().unwrap())
            .collect::<Vec<_>>(),
        ["/list/datum", "/list/list/datum", "/list"]
    );
    assert_eq!(rows[0].array_brackets().len(), 2);
    assert_eq!(rows[2].source_modifiers(), 8);
}
#[test]
fn primary_parameter_original_tokens_survive_unicode_comments_defaults_annotations_and_rebase() {
    let prefix = "// outside é漢\n";
    let source=format!("{prefix}/proc/p(var/* é漢 */ /datum/D = list(1, list(2,3)) as anything in list(1,2), text/T=\"(,as)\", ...)\n    return\n");
    let issued =
        crate::parse_proc_with_origins_at_span(&source, Span::new(prefix.len(), source.len()))
            .unwrap();
    let entries = issued.parameters.entries().unwrap();
    assert_eq!(entries.len(), 3);
    assert_eq!(&source[entries[0].name().range()], "D");
    assert_eq!(
        entries[0].type_path(&source).unwrap().as_deref(),
        Some("/datum")
    );
    assert!(entries[2].variadic());
    assert_eq!(&source[entries[2].name().range()], "...");
    assert_eq!(issued.parameters.header(), issued.item.header_span);
}
#[test]
fn primary_parameter_receipt_refuses_unsupported_or_ambiguous_source_not_empty_clean() {
    for source in [
        "/proc/p(/datum/D=1)\n    return\n",
        "/proc/p(/datum/D[])\n    return\n",
        "/proc/p(/datum/var/D)\n    return\n",
        "/proc/p(x,,y)\n    return\n",
    ] {
        match crate::parse_proc_with_origins_at_span(source, Span::new(0, source.len())) {
            Ok(p) => assert!(p.parameters.entries().is_err(), "{source}"),
            Err(_) => (),
        }
    }
}
#[test]
fn primary_parameter_receipt_storage_is_in_original_header_only_admission() {
    for count in [0, 1, 16, 256] {
        let args = (0..count)
            .map(|i| format!("static/datum/A{i}[]"))
            .collect::<Vec<_>>()
            .join(",");
        let source = format!("/proc/p({args})\n    return\n");
        let signature = signature(&source);
        signature.entries().unwrap();
        let bound = (signature.header().end - signature.header().start) * 64 + 128;
        assert!(signature.retained_bytes() <= bound);
        let mut exact =
            std::mem::size_of::<ParameterSignature>() + 2 * std::mem::size_of::<usize>();
        signature.visit_storage(|_, n| exact += n);
        assert_eq!(exact, signature.retained_bytes());
    }
}

#[test]
fn type_path_receipt_does_not_claim_default_or_dimension_expression_admission() {
    let source = "/proc/p(datum/D[bad ???] = bad ???)\n    return\n";
    let signature = signature(source);
    let entries = signature.entries().unwrap();
    assert_eq!(
        entries[0].type_path(source).unwrap().as_deref(),
        Some("/list/datum")
    );
}

#[test]
fn absolute_header_type_declarations_preserve_written_paths_and_skip_formal_ordinals() {
    let source="/proc/Heal(mob/living/M, /datum/affliction/contagion/engineered/A, actual_power=1)\n    return 1\n";
    let signature = signature(source);
    let entries = signature.entries().unwrap();
    assert_eq!(entries.len(), 2);
    assert_eq!(
        entries
            .iter()
            .map(|p| (&source[p.name().range()], p.ordinal(), p.source_modifiers()))
            .collect::<Vec<_>>(),
        [("M", 0, 0), ("actual_power", 1, 0)]
    );
    assert_eq!(
        entries[0].type_path(source).unwrap().as_deref(),
        Some("/mob/living")
    );
    assert_eq!(
        entries[1]
            .expressions()
            .unwrap()
            .unwrap()
            .default()
            .unwrap()
            .span
            .range(),
        source.find("=1").map(|at| at + 1..at + 2).unwrap()
    );
    let declarations = signature.absolute_declarations().unwrap();
    assert_eq!(declarations.len(), 1);
    assert_eq!(
        declarations[0].written_path(source).unwrap(),
        "/datum/affliction/contagion/engineered/A"
    );
}
#[test]
fn absolute_type_components_are_not_parameter_modifiers_and_invalid_suffixes_stay_refused() {
    for source in [
        "/proc/p(/datum/static/A, var/static/datum/D)\n    return\n",
        "/proc/p(/datum/SpacemanDMM_private/A, datum/static/D)\n    return\n",
    ] {
        let sig = signature(source);
        assert_eq!(sig.absolute_declarations().unwrap().len(), 1);
        assert_eq!(sig.entries().unwrap().len(), 1);
        assert!(sig.absolute_declarations().unwrap()[0]
            .written_path(source)
            .unwrap()
            .contains("/A"));
    }
    for bad in [
        "/datum/A[]",
        "/datum/A=1",
        "/datum/A as text",
        "/datum/A in world",
        "/datum/var/A",
        "/datum/proc/A",
        "/datum/verb/A",
        "/datum//A",
        "/datum/A/",
        "/datum /A",
        "/datum/A/*comment*/",
        "...,/datum/A",
    ] {
        let source = format!("/proc/p({bad})\n    return\n");
        if let Ok(parsed) =
            crate::parse_proc_with_origins_at_span(&source, Span::new(0, source.len()))
        {
            assert!(parsed.parameters.entries().is_err(), "{bad}");
        }
    }
}

#[test]fn original_parameter_type_cursor_is_the_actual_following_primary_token(){let source="/proc/p(missing/a, missing/b[1], missing/c=0, missing/d as num, missing/e in list())\n    return 0\n";let ast=crate::parse_declaration_skeleton(source);assert!(ast.diagnostics.is_empty());let original=crate::parse_proc_with_origins_from_spans(source,ast.items[0].span,&ast.tokens,0).unwrap();let entries=original.parameters.entries().unwrap();let expected=[(",","/missing"),("[","/list/missing"),("=","/missing"),("as","/missing"),("in","/missing")];assert_eq!(entries.len(),expected.len());for(parameter,(expected,path))in entries.iter().zip(expected){assert_eq!(&source[parameter.declaration_cursor().range()],expected);assert_eq!(parameter.type_path(source).unwrap().as_deref(),Some(path));}let last="/proc/p(missing/a)\n    return 0\n";let ast=crate::parse_declaration_skeleton(last);let original=crate::parse_proc_with_origins_from_spans(last,ast.items[0].span,&ast.tokens,0).unwrap();let at=original.parameters.entries().unwrap()[0].declaration_cursor();assert_eq!(&last[at.range()],")");}
