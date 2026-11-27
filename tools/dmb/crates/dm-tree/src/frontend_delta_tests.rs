use super::*;
use std::{collections::BTreeMap, path::Path};

struct Files {
    a: String,
    b: String,
}
impl dm_preprocess::SourceProvider for Files {
    fn read(&self, path: &Path) -> Result<String, String> {
        match path.file_name().and_then(|name| name.to_str()) {
            Some("a.dm") => Ok(self.a.clone()),
            Some("b.dm") => Ok(self.b.clone()),
            _ => Ok("#include \"a.dm\"\n#include \"b.dm\"\n".into()),
        }
    }
}

fn build(state: &mut RetainedSemanticTree, a: &str, b: &str) -> FrontendRevision {
    let executor = dm_exec::BuildExecutor::new(2).unwrap();
    let project = Path::new("delta.dme");
    let defines = BTreeMap::new();
    let built = build_with_executor_and_semantic_state(
        project,
        &Files { a: a.into(), b: b.into() },
        &defines,
        FrontendConfig { workers: 2, engine: None, observer: None },
        None,
        &executor,
        Some(state),
    )
    .unwrap();
    let revision = FrontendRevision::new(built);
    state.remember_frontend(project, &defines, revision.clone());
    revision
}

fn proc_key(file: &str, owner: &str, name: &str) -> DeclarationKey {
    DeclarationKey { file: Arc::from(file), owner: Arc::from(owner), member: Some((Arc::from(name), MemberKind::Proc)), ordinal: 0 }
}

const A: &str = "/datum/a\n/datum/a/proc/read()\n    return 1\n/datum/a/proc/other()\n    return 2\n";
const B: &str = "/datum/b\n/datum/b/var/count = 3\n";

#[test]
fn deltas_name_the_edited_files_declarations_and_bodies() {
    let mut state = RetainedSemanticTree::new();
    let first = build(&mut state, A, B);
    assert!(first.delta.is_none(), "a first revision has no base");

    // A body edit: one body changed, nothing else; the other file is not visited.
    let edited = A.replace("return 1", "return 7");
    let second = build(&mut state, &edited, B);
    let delta = second.delta.as_ref().expect("an edit after a remembered revision has a delta");
    assert_eq!((delta.base, delta.revision), (first.revision, second.revision));
    assert_eq!(delta.files, vec![Arc::<str>::from("a.dm")]);
    assert_eq!(delta.bodies, vec![(proc_key("a.dm", "/datum/a", "read"), Change::Changed)]);
    assert!(delta.declarations.iter().all(|(key, _)| key.member.as_ref().is_some_and(|(name, _)| &**name == "read")));

    // A line that shifts the rest of the file: the later body moved, its content did not change.
    let shifted = edited.replace("/datum/a/proc/other()", "// a comment line\n/datum/a/proc/other()");
    let third = build(&mut state, &shifted, B);
    let delta = third.delta.as_ref().unwrap();
    assert_eq!(delta.bodies, vec![(proc_key("a.dm", "/datum/a", "other"), Change::Moved)]);

    // A new var in the other file.
    let with_var = format!("{B}/datum/b/var/added = 4\n");
    let fourth = build(&mut state, &shifted, &with_var);
    let delta = fourth.delta.as_ref().unwrap();
    assert_eq!(delta.files, vec![Arc::<str>::from("b.dm")]);
    let added = DeclarationKey {
        file: Arc::from("b.dm"),
        owner: Arc::from("/datum/b"),
        member: Some((Arc::from("added"), MemberKind::Var)),
        ordinal: 0,
    };
    assert_eq!(delta.declarations, vec![(added.clone(), Change::Added)]);
    assert!(delta.bodies.is_empty());

    // A new proc: its declaration and its body are added.
    let with_proc = format!("{shifted}/datum/a/proc/third()\n    return 3\n");
    let fifth = build(&mut state, &with_proc, &with_var);
    let delta = fifth.delta.as_ref().unwrap();
    assert!(delta.declarations.contains(&(proc_key("a.dm", "/datum/a", "third"), Change::Added)), "{delta:?}");
    assert_eq!(delta.bodies, vec![(proc_key("a.dm", "/datum/a", "third"), Change::Added)]);

    // Everything since the first revision, chained; and nothing since the current one.
    let since = state.changes_since(first.revision).expect("the log reaches back to the first revision");
    assert_eq!(since.revision, fifth.revision);
    assert_eq!(since.files, vec![Arc::<str>::from("a.dm"), Arc::from("b.dm")]);
    assert!(since.declarations.contains(&(added, Change::Added)));
    assert!(since.bodies.contains(&(proc_key("a.dm", "/datum/a", "read"), Change::Changed)));
    assert!(state.changes_since(fifth.revision).unwrap().is_empty());
    assert!(state.changes_since(fifth.revision + 1).is_none());
}

/// A provider that names the files changed since the last revision, so the plan patches and the source index is reused (the
/// conditions under which origins are taken from the previous revision).
struct Revised<'a> {
    files: &'a Files,
    revision: u64,
    changed: std::collections::BTreeSet<std::path::PathBuf>,
}
impl dm_preprocess::SourceProvider for Revised<'_> {
    fn read(&self, path: &Path) -> Result<String, String> {
        self.files.read(path)
    }
    fn revision(&self) -> Option<u64> {
        Some(self.revision)
    }
    fn changes_since(&self, revision: u64) -> Option<Arc<std::collections::BTreeSet<std::path::PathBuf>>> {
        (revision + 1 == self.revision).then(|| Arc::new(self.changed.clone()))
    }
}

/// An in-memory expansion memo (region records, so the expansion carries receipts as the daemon's does).
#[derive(Default)]
struct Memo {
    inputs: dm_preprocess::regions::ExpansionInputs,
    records: std::sync::Mutex<BTreeMap<u128, Vec<Arc<dm_preprocess::regions::ExpansionRecord>>>>,
}
impl dm_preprocess::regions::ExpansionMemo for Memo {
    fn input_admissions(&self) -> Option<&dm_preprocess::regions::ExpansionInputs> {
        Some(&self.inputs)
    }
    fn candidates(&self, key: u128) -> Vec<Arc<dm_preprocess::regions::ExpansionRecord>> {
        self.records.lock().unwrap().get(&key).cloned().unwrap_or_default()
    }
    fn insert(&self, record: Arc<dm_preprocess::regions::ExpansionRecord>) {
        self.records.lock().unwrap().entry(record.key()).or_default().push(record);
    }
}

fn build_revised(state: Option<(&mut RetainedSemanticTree, &Memo)>, files: &Files, revision: u64, changed: &[&str]) -> FrontendRevision {
    let executor = dm_exec::BuildExecutor::new(2).unwrap();
    let project = Path::new("delta.dme");
    let defines = BTreeMap::new();
    let provider = Revised {
        files,
        revision,
        changed: changed.iter().map(|name| dm_preprocess::regions::canonical_path(Path::new(name))).collect(),
    };
    let mut one_shot = RetainedSemanticTree::new();
    let cold_memo = Memo::default();
    let retained = state.is_some();
    let (state, memo) = match state {
        Some((state, memo)) => (state, memo),
        None => (&mut one_shot, &cold_memo),
    };
    let built = build_with_executor_and_semantic_state(
        project,
        &provider,
        &defines,
        FrontendConfig { workers: 2, engine: None, observer: None },
        Some(memo as &dyn dm_preprocess::regions::ExpansionMemo),
        &executor,
        Some(&mut *state),
    )
    .unwrap();
    let revision = FrontendRevision::new(built);
    if retained {
        state.remember_frontend(project, &defines, revision.clone());
    }
    revision
}

fn same_origins(incremental: &ColdFrontend, cold: &ColdFrontend) {
    let count = incremental.snapshot.tree.declarations().len();
    assert_eq!(count, cold.snapshot.tree.declarations().len());
    for index in 0..count {
        let id = OccurrenceId(index as u32);
        assert_eq!(
            incremental.snapshot.occurrences.get(id).map(|o| &o.provenance),
            cold.snapshot.occurrences.get(id).map(|o| &o.provenance),
            "declaration {index}"
        );
    }
    assert_eq!(incremental.declaration_regions, cold.declaration_regions);
    assert_eq!(incremental.bodies.len(), cold.bodies.len());
    for (now, fresh) in incremental.bodies.iter().zip(cold.bodies.iter()) {
        assert_eq!(now.declaration, fresh.declaration);
        assert_eq!(now.expanded_span, fresh.expanded_span);
        assert_eq!(now.source, fresh.source);
        assert_eq!(now.setting_context_origins, fresh.setting_context_origins);
    }
    assert_eq!(incremental.region_hashes, cold.region_hashes);
}

/// The declarations themselves (what the carried chunks' contributions supply): the same skeletons, symbols, member tree,
/// body terminations and expanded text as a cold build.
fn same_declarations(incremental: &ColdFrontend, cold: &ColdFrontend) {
    assert_eq!(incremental.expanded.text.as_str(), cold.expanded.text.as_str());
    let (tree, fresh) = (&incremental.snapshot.tree, &cold.snapshot.tree);
    assert_eq!(tree.declarations(), fresh.declarations());
    assert_eq!(tree.symbols().ordered(), fresh.symbols().ordered());
    assert_eq!(incremental.declaration_starts, cold.declaration_starts);
    for (now, was) in incremental.bodies.iter().zip(cold.bodies.iter()) {
        assert_eq!(now.member, was.member);
        assert_eq!(now.ast_path, was.ast_path);
    }
    let terminations = |frontend: &ColdFrontend| {
        frontend.issued_body_codes.iter().map(|owner| owner.termination.canonical_tag()).collect::<Vec<_>>()
    };
    assert_eq!(terminations(incremental), terminations(cold));
}

#[test]
fn reused_origins_equal_a_cold_build_through_edits() {
    reused_origins_through_edits(1);
}

/// Revisions the provider cannot relate (no change log): the ordered pass adopts the unchanged subtrees instead of
/// patching, and the source index is rebuilt with the same numbering.
#[test]
fn reused_origins_equal_a_cold_build_after_adoption() {
    reused_origins_through_edits(10);
}

fn reused_origins_through_edits(stride: u64) {
    let many: String = (0..40).map(|i| format!("/datum/b{i}\n/datum/b{i}/proc/p()\n    return {i}\n")).collect();
    let mut state = RetainedSemanticTree::new();
    let memo = Memo::default();
    let mut files = Files { a: A.into(), b: many.clone() };
    build_revised(Some((&mut state, &memo)), &files, stride, &[]);
    let steps: Vec<(String, String, Vec<&str>)> = vec![
        (A.replace("return 1", "return 7"), many.clone(), vec!["a.dm"]),
        (A.replace("return 1", "return 7").replace("/datum/a/proc/other()", "// shift\n/datum/a/proc/other()"), many.clone(), vec!["a.dm"]),
        (A.replace("return 1", "return 7"), format!("// top\n{many}"), vec!["a.dm", "b.dm"]),
        (A.into(), format!("// top\n{many}/datum/b0/var/added = 1\n"), vec!["a.dm", "b.dm"]),
        (A.into(), format!("// top\n{}/datum/b0/var/added = 1\n", many.replace("return 5", "return 55")), vec!["b.dm"]),
    ];
    let mut reused = 0;
    let mut carried = 0;
    let mut terminations = 0;
    for (revision, (a, b, changed)) in steps.into_iter().enumerate() {
        files = Files { a, b };
        let revision = (revision as u64 + 2) * stride;
        let incremental = build_revised(Some((&mut state, &memo)), &files, revision, &changed);
        reused += incremental.timings.reused_origins;
        carried += incremental.timings.declaration_reuse.carried_chunks;
        terminations += incremental.timings.reused_terminations;
        let cold = build_revised(None, &files, revision, &[]);
        same_origins(&incremental, &cold);
        same_declarations(&incremental, &cold);
    }
    // The reuse ran: an unchanged file's origins came from the previous revision.
    assert!(reused > 0);
    // Chunks the expansion copied took their key and contribution from the previous request's chunk table (the patch
    // path; the adoption path re-expands through the ordered pass but still copies unchanged regions).
    assert!(carried > 0, "no chunk was carried");
    // Bodies inside interior carried chunks kept their previous termination (and `same_declarations` compared them).
    assert!(terminations > 0, "no body termination was reused");
}
