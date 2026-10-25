use super::*;
use std::sync::Mutex;

struct Prepared {
    files: BTreeMap<PathBuf, Arc<prepared_source::PreparedSource>>,
    revision: u64,
    /// Every revision's changed files, as a query database keeps them.
    log: Arc<Vec<(u64, BTreeSet<PathBuf>)>>,
    report: bool,
}
impl Prepared {
    /// Unchanged text keeps the previous request's preparation, as a retaining provider does.
    fn new(files: &[(&str, &str)], previous: Option<&Prepared>) -> Self {
        let files: BTreeMap<_, _> = files
            .iter()
            .map(|(path, text)| {
                let path = PathBuf::from(path);
                let kept = previous
                    .and_then(|previous| previous.files.get(&path))
                    .filter(|kept| kept.original().as_str() == *text)
                    .cloned();
                let prepared = kept.unwrap_or_else(|| {
                    Arc::new(prepared_source::PreparedSource::from_text(
                        crate::SourceText::from(*text),
                    ))
                });
                (path, prepared)
            })
            .collect();
        let (revision, log) = match previous {
            None => (1, Arc::new(Vec::new())),
            Some(previous) => {
                let mut changed = BTreeSet::new();
                for (path, now) in &files {
                    let same = previous
                        .files
                        .get(path)
                        .is_some_and(|before| Arc::ptr_eq(before, now));
                    if !same {
                        changed.insert(path.clone());
                    }
                }
                for path in previous.files.keys() {
                    if !files.contains_key(path) {
                        changed.insert(path.clone());
                    }
                }
                let mut log = previous.log.as_ref().clone();
                log.push((previous.revision + 1, changed));
                (previous.revision + 1, Arc::new(log))
            }
        };
        Self {
            files,
            revision,
            log,
            report: true,
        }
    }
    /// The same inputs, but a provider that cannot say what changed.
    fn silent(&self) -> Self {
        Self {
            files: self.files.clone(),
            revision: self.revision,
            log: Arc::clone(&self.log),
            report: false,
        }
    }
}
impl SourceProvider for Prepared {
    fn read(&self, path: &Path) -> Result<String, String> {
        self.files
            .get(path)
            .map(|prepared| prepared.original().as_str().to_string())
            .ok_or_else(|| "missing".into())
    }
    fn prepared_source(&self, path: &Path) -> Option<Arc<prepared_source::PreparedSource>> {
        self.files.get(path).cloned()
    }
    fn revision(&self) -> Option<u64> {
        self.report.then_some(self.revision)
    }
    fn changes_since(&self, revision: u64) -> Option<Arc<BTreeSet<PathBuf>>> {
        if !self.report {
            return None;
        }
        let mut changed = BTreeSet::new();
        for (at, paths) in self.log.iter() {
            if *at > revision {
                changed.extend(paths.iter().cloned());
            }
        }
        Some(Arc::new(changed))
    }
}
#[derive(Default)]
struct Memo {
    inputs: ExpansionInputs,
    records: Mutex<BTreeMap<u128, Vec<Arc<ExpansionRecord>>>>,
}
impl ExpansionMemo for Memo {
    fn input_admissions(&self) -> Option<&ExpansionInputs> {
        Some(&self.inputs)
    }
    fn candidates(&self, key: u128) -> Vec<Arc<ExpansionRecord>> {
        self.records.lock().unwrap().get(&key).cloned().unwrap_or_default()
    }
    fn insert(&self, record: Arc<ExpansionRecord>) {
        self.records.lock().unwrap().entry(record.key()).or_default().push(record);
    }
}

const MANIFEST: &str =
    "#define N 3\n#include \"a.dm\"\n#include \"dir/b.dm\"\n#include \"c.dm\"\n#include \"tail.dm\"\n";
const A: &str = "/proc/a()\n    return N\n";
const B: &str = "#define LOCAL 5\n/proc/b()\n    return LOCAL\n#include \"b_child.dm\"\n/proc/b_after()\n    return N\n#undef LOCAL\n";
const B_CHILD: &str = "/proc/b_child()\n    return LOCAL\n";
const C: &str = "#ifdef N\n/proc/c()\n    return 1\n#else\n/proc/c()\n    return 2\n#endif\n";
const TAIL: &str = "/proc/tail()\n    return N + 1\n/datum/tail_type\n    var/v = N\n";

fn world<'a>(
    manifest: &'a str,
    a: &'a str,
    b: &'a str,
    b_child: &'a str,
    c: &'a str,
    tail: &'a str,
) -> Vec<(&'static str, &'a str)> {
    vec![
        ("project.dme", manifest),
        ("a.dm", a),
        ("dir/b.dm", b),
        ("dir/b_child.dm", b_child),
        ("c.dm", c),
        ("tail.dm", tail),
        ("d.dm", "/proc/d()\n    return N * 2\n"),
        ("r.dm", "#pragma multiple\n/proc/r()\n    return N\n"),
    ]
}
fn defaults<'a>() -> Vec<(&'static str, &'a str)> {
    world(MANIFEST, A, B, B_CHILD, C, TAIL)
}
fn full(provider: &Prepared, memo: &Memo) -> (DirectivePlan, ExpandedRegions) {
    let plan = plan_regions_with_memo(Path::new("project.dme"), provider, &BTreeMap::new(), memo);
    assert!(plan.diagnostics.is_empty(), "{:?}", plan.diagnostics);
    let expanded = expand_regions_text_with_memo(&plan, 2, memo);
    (plan, expanded)
}
struct Step {
    plan: DirectivePlan,
    expanded: ExpandedRegions,
    provider: Prepared,
    reuse: PlanReuse,
    /// What the ordered pass alone reused (it runs when nothing says what changed).
    walked: PlanReuse,
    expansion: Option<ExpansionReuse>,
}
/// One request: the incremental plan and expansion against the previous step, each proven equal
/// to a full pass over the same files.
fn request(previous: &Step, files: &[(&str, &str)], memo: &Memo) -> Step {
    let provider = Prepared::new(files, Some(&previous.provider));
    let (full_plan, full_expanded) = full(&provider, memo);
    // The ordered pass alone (a provider that cannot say what changed), then the patch.
    let silent = provider.silent();
    let (walked, walked_reuse) = plan_regions_incremental(
        Path::new("project.dme"),
        &silent,
        &BTreeMap::new(),
        Some(memo),
        Some(&previous.plan),
    );
    plans_equal(&walked, &full_plan).unwrap_or_else(|why| panic!("walked plan {why}"));
    assert_eq!(walked_reuse.replanned, 0);
    let (plan, reuse) = plan_regions_incremental(
        Path::new("project.dme"),
        &provider,
        &BTreeMap::new(),
        Some(memo),
        Some(&previous.plan),
    );
    plans_equal(&plan, &full_plan).unwrap_or_else(|why| panic!("plan {why}"));
    let executor = dm_exec::BuildExecutor::new(2).unwrap();
    let reusing =
        expand_regions_reusing(&previous.expanded, &plan, &reuse, memo, &executor);
    let expansion = reusing.as_ref().map(|(_, stats)| *stats);
    let expanded = match reusing {
        Some((expanded, _)) => {
            expansions_equal(&expanded, &full_expanded)
                .unwrap_or_else(|why| panic!("expansion {why}"));
            expanded
        }
        None => full_expanded,
    };
    Step {
        plan,
        expanded,
        provider,
        reuse,
        walked: walked_reuse,
        expansion,
    }
}
fn first(files: &[(&str, &str)], memo: &Memo) -> Step {
    let provider = Prepared::new(files, None);
    let (plan, expanded) = full(&provider, memo);
    let (again, reuse) = plan_regions_incremental(
        Path::new("project.dme"),
        &provider,
        &BTreeMap::new(),
        Some(memo),
        None,
    );
    plans_equal(&again, &plan).unwrap();
    assert_eq!(reuse.subtrees, 0);
    Step {
        plan,
        expanded,
        provider,
        reuse,
        walked: PlanReuse::default(),
        expansion: None,
    }
}

#[test]
fn leaf_edit_adopts_every_other_subtree_and_equals_the_full_pass() {
    let memo = Memo::default();
    let zero = first(&defaults(), &memo);
    let one = request(
        &zero,
        &world(MANIFEST, "/proc/a()\n    return N + 9\n", B, B_CHILD, C, TAIL),
        &memo,
    );
    // The ordered pass adopts the other three children of the manifest whole; only a.dm ran again.
    assert_eq!(one.walked.subtrees, 3, "{:?}", one.walked);
    // With the change log only a.dm is planned again: the rest of the plan is the previous one.
    assert_eq!(one.reuse.replanned, 1, "{:?}", one.reuse);
    assert!(one.reuse.copied_regions >= 7, "{:?}", one.reuse);
    // The manifest's own regions, between its includes, equal the previous plan's.
    assert!(one.walked.matched_regions >= 5, "{:?}", one.walked);
    let stats = one.expansion.expect("expansion reuses the copied regions");
    // Only the edited file's region is expanded again.
    assert_eq!(stats.expanded, 1, "{stats:?}");
    // The same edit again: the subtree is a record of the previous request now.
    let two = request(
        &one,
        &world(MANIFEST, "/proc/a()\n    return N + 10\n", B, B_CHILD, C, TAIL),
        &memo,
    );
    assert_eq!(two.walked.subtrees, 3);
    assert_eq!(two.reuse.replanned, 1);
}

#[test]
fn edits_inside_files_with_directives_and_nested_includes_stay_equal() {
    let memo = Memo::default();
    let mut step = first(&defaults(), &memo);
    let edits: Vec<(&str, Vec<(&str, &str)>)> = vec![
        ("nested child", world(MANIFEST, A, B, "/proc/b_child()\n    return LOCAL + 1\n", C, TAIL)),
        (
            "parent text after its define",
            world(
                MANIFEST,
                A,
                "#define LOCAL 5\n/proc/b()\n    return LOCAL * 2\n#include \"b_child.dm\"\n/proc/b_after()\n    return N\n#undef LOCAL\n",
                "/proc/b_child()\n    return LOCAL + 1\n",
                C,
                TAIL,
            ),
        ),
        (
            "a line above the define moves its definition site",
            world(
                MANIFEST,
                A,
                "// moved\n#define LOCAL 5\n/proc/b()\n    return LOCAL * 2\n#include \"b_child.dm\"\n/proc/b_after()\n    return N\n#undef LOCAL\n",
                "/proc/b_child()\n    return LOCAL + 1\n",
                C,
                TAIL,
            ),
        ),
        (
            "conditional flips",
            world(
                MANIFEST,
                A,
                "// moved\n#define LOCAL 5\n/proc/b()\n    return LOCAL * 2\n#include \"b_child.dm\"\n/proc/b_after()\n    return N\n#undef LOCAL\n",
                "/proc/b_child()\n    return LOCAL + 1\n",
                "#ifndef N\n/proc/c()\n    return 1\n#else\n/proc/c()\n    return 2\n#endif\n",
                TAIL,
            ),
        ),
    ];
    for (label, files) in edits {
        step = request(&step, &files, &memo);
        assert!(
            step.walked.subtrees > 0 || step.reuse.replanned > 0,
            "{label}: {:?} {:?}",
            step.walked,
            step.reuse
        );
    }
}

#[test]
fn manifest_changes_renumber_adopted_subtrees_or_decline_them() {
    let memo = Memo::default();
    let zero = first(&defaults(), &memo);
    // A define in the manifest changes the state every later subtree starts from.
    let redefined = request(
        &zero,
        &world(
            "#define N 4\n#include \"a.dm\"\n#include \"dir/b.dm\"\n#include \"c.dm\"\n#include \"tail.dm\"\n",
            A,
            B,
            B_CHILD,
            C,
            TAIL,
        ),
        &memo,
    );
    assert_eq!(redefined.walked.subtrees, 0);
    assert_eq!(redefined.reuse.replanned, 0, "the manifest changed: no patch");
    // A new include in the middle moves every later subtree; they are adopted renumbered.
    let inserted = request(
        &zero,
        &world(
            "#define N 3\n#include \"a.dm\"\n#include \"d.dm\"\n#include \"dir/b.dm\"\n#include \"c.dm\"\n#include \"tail.dm\"\n",
            A,
            B,
            B_CHILD,
            C,
            TAIL,
        ),
        &memo,
    );
    assert!(inserted.walked.subtrees >= 3, "{:?}", inserted.walked);
    assert!(
        inserted
            .walked
            .regions
            .iter()
            .enumerate()
            .any(|(now, was)| was.is_some_and(|was| was != now)),
        "some copied region moved to another index"
    );
    // Removing it again, reordering, and a repeated include of a `#pragma multiple` file.
    let removed = request(&inserted, &defaults(), &memo);
    assert!(removed.walked.subtrees >= 3);
    let reordered = request(
        &removed,
        &world(
            "#define N 3\n#include \"c.dm\"\n#include \"a.dm\"\n#include \"dir/b.dm\"\n#include \"tail.dm\"\n",
            A,
            B,
            B_CHILD,
            C,
            TAIL,
        ),
        &memo,
    );
    let repeated = request(
        &reordered,
        &world(
            "#define N 3\n#include \"c.dm\"\n#include \"r.dm\"\n#include \"a.dm\"\n#include \"r.dm\"\n#include \"dir/b.dm\"\n#include \"tail.dm\"\n",
            A,
            B,
            B_CHILD,
            C,
            TAIL,
        ),
        &memo,
    );
    let _ = request(
        &repeated,
        &world(
            "#define N 3\n#include \"c.dm\"\n#include \"r.dm\"\n#include \"a.dm\"\n#include \"r.dm\"\n#include \"dir/b.dm\"\n#include \"tail.dm\"\n",
            "/proc/a()\n    return N + 5\n",
            B,
            B_CHILD,
            C,
            TAIL,
        ),
        &memo,
    );
}

#[test]
fn a_file_included_twice_is_include_once_and_follows_the_first_visit() {
    let memo = Memo::default();
    let twice = |a: &'static str| {
        world(
            "#define N 3\n#include \"a.dm\"\n#include \"c.dm\"\n#include \"a.dm\"\n#include \"tail.dm\"\n",
            a,
            B,
            B_CHILD,
            C,
            TAIL,
        )
    };
    let zero = first(&twice(A), &memo);
    let edited = request(&zero, &twice("/proc/a()\n    return N + 2\n"), &memo);
    assert!(edited.walked.subtrees >= 2 || edited.reuse.replanned > 0);
    // Dropping the first include moves the real visit to the second one.
    let moved = request(
        &edited,
        &world(
            "#define N 3\n#include \"c.dm\"\n#include \"a.dm\"\n#include \"tail.dm\"\n",
            "/proc/a()\n    return N + 2\n",
            B,
            B_CHILD,
            C,
            TAIL,
        ),
        &memo,
    );
    let _ = moved;
}

#[test]
fn a_changed_manifest_line_before_an_adopted_subtree_keeps_the_cursors_exact() {
    // Include-return and end-of-file cursors carry absolute ordered-item positions: they must be
    // renumbered with the subtree, which `plans_equal` checks through the occurrence dump.
    let memo = Memo::default();
    let zero = first(&defaults(), &memo);
    let shifted = request(
        &zero,
        &world(
            "#define N 3\n/* a comment line */\n#include \"a.dm\"\n#include \"d.dm\"\n#include \"dir/b.dm\"\n#include \"c.dm\"\n#include \"tail.dm\"\n",
            A,
            B,
            B_CHILD,
            C,
            TAIL,
        ),
        &memo,
    );
    assert!(shifted.walked.subtrees >= 3);
    assert!(shifted.expansion.is_some());
}
