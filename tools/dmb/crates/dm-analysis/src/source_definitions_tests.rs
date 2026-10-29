use super::*;
use dm_tree::frontend::build;
use std::sync::Arc;
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
fn archive(source: &'static str) -> Arc<BodyArchive> {
    build(
        Path::new("code/definitions.dm"),
        &Source(source),
        &Default::default(),
        1,
    )
    .unwrap()
    .body_archive()
    .unwrap()
}
fn owners(index: &SourceDefinitionIndex<'_>, line: usize) -> Vec<String> {
    index
        .owner_candidates("code/definitions.dm", line)
        .iter()
        .map(|&id| {
            index
                .archive()
                .tree()
                .symbols()
                .text(id)
                .unwrap()
                .to_owned()
        })
        .collect()
}

#[test]
fn source_definition_index_includes_own_vars_and_all_callable_kinds() {
    let a = archive("var/global_value\n/datum/a\n    var/value\n    proc/read()\n        return\n    verb/act()\n        return\n");
    let index = SourceDefinitionIndex::capture(&a, Path::new(".")).unwrap();
    let rows = index.defs_in("code/definitions.dm");
    assert_eq!(
        rows.iter()
            .map(|r| (r.line(), r.owner_text(), r.name_text(), r.kind()))
            .collect::<Vec<_>>(),
        [
            (1, "/", "global_value", MemberKind::Var),
            (3, "/datum/a", "value", MemberKind::Var),
            (4, "/datum/a", "read", MemberKind::Proc),
            (6, "/datum/a", "act", MemberKind::Verb)
        ]
    );
    assert_eq!(
        index.reader_ident("code/definitions.dm", 1),
        "/::global_value"
    );
}

#[test]
fn candidates_look_backward_then_forward_and_deduplicate_only_owner_values() {
    let a = archive(
        "/datum/a\n    var/one\n    proc/read()\n        return\n\n/datum/b\n    var/two\n",
    );
    let index = SourceDefinitionIndex::capture(&a, Path::new(".")).unwrap();
    assert_eq!(owners(&index, 1), ["/datum/a"]);
    assert_eq!(owners(&index, 2), ["/datum/a"]);
    assert_eq!(owners(&index, 5), ["/datum/a", "/datum/b"]);
    assert_eq!(owners(&index, 99), ["/datum/b"]);
    assert!(index.owner_candidates("missing.dm", 1).is_empty());
}

#[test]
fn bare_type_headers_do_not_replace_definition_candidates_or_reader_identity() {
    let a =
        archive("/datum/a\n    var/one\n/datum/empty\n/datum/b\n    proc/read()\n        return\n");
    let index = SourceDefinitionIndex::capture(&a, Path::new(".")).unwrap();
    assert_eq!(owners(&index, 3), ["/datum/a", "/datum/b"]);
    assert_eq!(
        index.reader_ident("code/definitions.dm", 3),
        "/datum/a::one"
    );
    assert_eq!(index.reader_ident("code/definitions.dm", 0), "?");
    assert_eq!(index.reader_ident("missing.dm", 20), "?");
}

#[test]
fn variable_defaults_are_not_new_declarations_and_inherited_procs_are_not_copies() {
    let a = archive("/datum/base\n    var/value = 1\n    proc/read()\n        return\n/datum/base/child\n    value = 2\n/datum/base/other\n    read()\n        return\n");
    let index = SourceDefinitionIndex::capture(&a, Path::new(".")).unwrap();
    assert_eq!(
        index
            .defs_in("code/definitions.dm")
            .iter()
            .map(|r| (r.line(), r.owner_text(), r.name_text()))
            .collect::<Vec<_>>(),
        [
            (2, "/datum/base", "value"),
            (3, "/datum/base", "read"),
            (8, "/datum/base/other", "read")
        ]
    );
}

#[test]
fn macro_origins_are_retained_without_reconstructing_locations() {
    let a = archive("#define MAKE_VALUE var/value = 1\n/datum/a\n    MAKE_VALUE\n");
    let index = SourceDefinitionIndex::capture(&a, Path::new(".")).unwrap();
    let row = index.defs_in("code/definitions.dm")[0];
    assert_eq!(row.line(), 3);
    let origin = row.origin().unwrap();
    assert_eq!(origin.line, 3);
    assert!(!origin.macro_expansions.is_empty());
}

#[test]
fn source_definition_index_never_demands_executable_syntax() {
    #[derive(Debug)]
    struct NoSyntax;
    impl dm_tree::frontend::BodySyntaxQueries for NoSyntax {
        fn syntax(
            &self,
            _: &Arc<dm_tree::frontend::BodySyntaxInput>,
        ) -> Result<Arc<dm_tree::frontend::BodySyntax>, dm_tree::frontend::Diagnostic> {
            panic!("source definition policy tried to parse a body")
        }
    }
    let frontend = build(
        Path::new("code/definitions.dm"),
        &Source("/datum/a/proc/read()\n    return 1\n"),
        &Default::default(),
        1,
    )
    .unwrap()
    .with_body_queries(Arc::new(NoSyntax));
    let a = frontend.body_archive().unwrap();
    let index = SourceDefinitionIndex::capture(&a, Path::new(".")).unwrap();
    assert_eq!(
        index.reader_ident("code/definitions.dm", 2),
        "/datum/a::read"
    );
}

#[test]
fn source_definition_rows_keep_their_own_archive_binding_after_frontend_release() {
    let a = archive("/datum/a\n    var/value\n    proc/read()\n        return\n");
    let index = SourceDefinitionIndex::capture(&a, Path::new(".")).unwrap();
    let foreign = archive("/datum/b\n    var/value\n    proc/read()\n        return\n");
    let row = index.defs_in("code/definitions.dm")[0];
    assert_eq!(row.owner_text(), "/datum/a");
    assert_eq!(
        foreign.tree().symbols().text(SymbolId::of("/datum/b")),
        Some("/datum/b")
    );
    assert_eq!(row.origin().unwrap().line, 2);
}

#[test]
fn callable_origin_uses_body_roster_ordinal_not_declaration_ordinal() {
    let a = archive("/datum/a\n    var/one\n    var/two\n    proc/read()\n        return\n    proc/write()\n        return\n");
    let index = SourceDefinitionIndex::capture(&a, Path::new(".")).unwrap();
    let rows = index.defs_in("code/definitions.dm");
    let read = rows.iter().find(|row| row.name_text() == "read").unwrap();
    let write = rows.iter().find(|row| row.name_text() == "write").unwrap();
    assert_eq!(read.origin().unwrap().line, 4);
    assert_eq!(write.origin().unwrap().line, 6);
    assert_eq!(read.member(), a.occurrences()[0].member);
    assert_eq!(write.member(), a.occurrences()[1].member);
    assert_ne!(
        a.occurrences()[0].declaration.0,
        0,
        "fixture needs preceding non-body declarations"
    );
}

#[test]
fn same_line_definition_ties_match_vars_first_and_formal_first_policy() {
    let a = archive("/datum/a/value() { return 2; }; /datum/a/proc/value() { return 1; }; /datum/a/var/value = 7\n");
    let index = SourceDefinitionIndex::capture(&a, Path::new(".")).unwrap();
    let rows = index.defs_in("code/definitions.dm");
    assert_eq!(rows.len(), 3);
    assert_eq!(
        rows.iter()
            .map(|r| (r.line(), r.owner_text(), r.name_text()))
            .collect::<Vec<_>>(),
        [
            (1, "/datum/a", "value"),
            (1, "/datum/a", "value"),
            (1, "/datum/a", "value")
        ]
    );
    assert_eq!(rows[0].kind(), MemberKind::Var);
    assert_eq!(rows[0].procedure_ordinal(), None);
    assert_eq!(rows[1].procedure_ordinal(), Some(0));
    assert_eq!(rows[2].procedure_ordinal(), Some(1));
    assert_eq!(
        a.tree().member(rows[1].member()).unwrap().definition,
        DefinitionMode::Declare
    );
    assert_ne!(
        a.tree().member(rows[2].member()).unwrap().definition,
        DefinitionMode::Declare
    );
}

#[test]
fn canonical_include_paths_use_legacy_relative_slash_keys() {
    struct Files;
    impl dm_preprocess::SourceProvider for Files {
        fn read(&self, path: &Path) -> Result<String, String> {
            Ok(match path.file_name().and_then(|s| s.to_str()) {
                Some("project.dme") => "#include \"code/child/../part.dm\"\n",
                Some("part.dm") => "/datum/a\n    var/value\n",
                _ => return Err(format!("unexpected fixture path {}", path.display())),
            }
            .into())
        }
    }
    let frontend = build(
        Path::new("workspace/project.dme"),
        &Files,
        &Default::default(),
        1,
    )
    .unwrap();
    let a = frontend.body_archive().unwrap();
    let index = SourceDefinitionIndex::capture(&a, Path::new("workspace")).unwrap();
    assert_eq!(
        index.files().map(|(path, _)| path).collect::<Vec<_>>(),
        ["code/part.dm"]
    );
    assert_eq!(index.reader_ident("code/part.dm", 2), "/datum/a::value");
}

#[test]
fn crlf_source_coordinates_are_not_counted_twice_by_definition_queries() {
    let a = archive("/datum/a\r\n    var/value\r\n    proc/read()\r\n        return\r\n");
    let index = SourceDefinitionIndex::capture(&a, Path::new(".")).unwrap();
    assert_eq!(
        index
            .defs_in("code/definitions.dm")
            .iter()
            .map(|row| row.line())
            .collect::<Vec<_>>(),
        [2, 3]
    );
    assert_eq!(
        index
            .def_at("code/definitions.dm", 3)
            .unwrap()
            .origin()
            .unwrap()
            .line,
        3
    );
}

#[cfg(windows)]
#[test]
fn report_path_uses_safe_dos_verbatim_equivalence_only() {
    let a = archive("/datum/probe/proc/run()\n    return\n");
    let mut source = a.occurrences()[0].source.clone();
    source.path = std::sync::Arc::new(Path::new(r"\\?\E:\policy-report\code\probe.dm").to_path_buf());
    assert_eq!(file(Path::new(r"E:\policy-report"), &source), "code/probe.dm");
    source.path = std::sync::Arc::new(Path::new(r"\\.\E:\policy-report\code\probe.dm").to_path_buf());
    assert_ne!(file(Path::new(r"E:\policy-report"), &source), "code/probe.dm");
}
