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
