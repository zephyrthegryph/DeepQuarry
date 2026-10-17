use super::*;
use std::sync::Mutex;

struct Prepared(BTreeMap<PathBuf, Arc<prepared_source::PreparedSource>>);
impl Prepared {
    /// Unchanged text keeps the previous request's preparation, as a retaining provider does.
    fn new(files: &[(&str, &str)], previous: Option<&Prepared>) -> Self {
        Self(
            files
                .iter()
                .map(|(path, text)| {
                    let path = PathBuf::from(path);
                    let kept = previous
                        .and_then(|previous| previous.0.get(&path))
                        .filter(|kept| kept.original().as_str() == *text)
                        .cloned();
                    let prepared = kept.unwrap_or_else(|| {
                        Arc::new(prepared_source::PreparedSource::from_text(crate::SourceText::from(*text)))
                    });
                    (path, prepared)
                })
                .collect(),
        )
    }
}
impl SourceProvider for Prepared {
    fn read(&self, path: &Path) -> Result<String, String> {
        self.0
            .get(path)
            .map(|prepared| prepared.original().as_str().to_string())
            .ok_or_else(|| "missing".into())
    }
    fn prepared_source(&self, path: &Path) -> Option<Arc<prepared_source::PreparedSource>> {
        self.0.get(path).cloned()
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

const PROJECT: &str = "#define N 3\n#include \"a.dm\"\n#include \"b.dm\"\n#include \"c.dm\"\n";
fn files<'a>(a: &'a str, b: &'a str, c: &'a str) -> Vec<(&'static str, &'a str)> {
    vec![("project.dme", PROJECT), ("a.dm", a), ("b.dm", b), ("c.dm", c)]
}
fn full(provider: &Prepared, memo: &Memo) -> (DirectivePlan, ExpandedRegions) {
    let plan = plan_regions_with_memo(Path::new("project.dme"), provider, &BTreeMap::new(), memo);
    assert!(plan.diagnostics.is_empty(), "{:?}", plan.diagnostics);
    let expanded = expand_regions_text_with_memo(&plan, 2, memo);
    (plan, expanded)
}

#[test]
fn leaf_edits_equal_the_full_plan_and_expansion_through_a_chain() {
    let memo = Memo::default();
    let a = "/proc/a()\n    return N\n";
    let c = "/proc/c()\n    return N + 1\n/datum/c_type\n    var/v = N\n";
    let b0 = "/proc/b()\n    return 1\n";
    let first = Prepared::new(&files(a, b0, c), None);
    let (plan0, expanded0) = full(&first, &memo);
    // Longer, with a macro use and a new line count, then shorter again, then an empty file.
    let (mut plan, mut expanded, mut provider) = (plan0, expanded0, first);
    for b in [
        "/proc/b()\n    return N * 2\n/proc/b2()\n    return 5\n",
        "/proc/b()\n    return 1\n",
        "",
    ] {
        let next = Prepared::new(&files(a, b, c), Some(&provider));
        let (full_plan, full_expanded) = full(&next, &memo);
        let edit = plan_regions_edit(&plan, &next).unwrap_or_else(|| panic!("no edit for {b:?}"));
        plans_equal(&edit.plan, &full_plan, &edit.regions).unwrap_or_else(|why| panic!("{b:?}: plan {why}"));
        let edited = expand_regions_edit(&expanded, &edit.plan, &edit.regions, &memo)
            .unwrap_or_else(|| panic!("no expansion edit for {b:?}"));
        expansions_equal(&edited, &full_expanded).unwrap_or_else(|why| panic!("{b:?}: expansion {why}"));
        (plan, expanded, provider) = (edit.plan, edited, next);
    }
    // An empty region has no segment, so no macro environment to reuse: the next edit declines.
    let refilled = Prepared::new(&files(a, "/proc/b()
    return 3
", c), Some(&provider));
    assert!(plan_regions_edit(&plan, &refilled).is_none());
    let _ = expanded;
}

#[test]
fn edits_that_touch_directives_or_structure_decline() {
    let memo = Memo::default();
    let a = "/proc/a()\n    return N\n";
    let b = "/proc/b()\n    return 1\n";
    let c = "/proc/c()\n    return 2\n";
    let first = Prepared::new(&files(a, b, c), None);
    let (plan, _) = full(&first, &memo);
    for (label, changed) in [
        ("directive added", files(a, "#define X 1\n/proc/b()\n    return X\n", c)),
        ("conditional added", files(a, "#ifdef N\n/proc/b()\n    return 1\n#endif\n", c)),
    ] {
        let next = Prepared::new(&changed, Some(&first));
        assert!(plan_regions_edit(&plan, &next).is_none(), "{label}");
    }
    // The old text of the changed file held a directive.
    let with_directive = Prepared::new(&files(a, "#define X 1\n/proc/b()\n    return X\n", c), None);
    let (directive_plan, _) = full(&with_directive, &memo);
    let back = Prepared::new(&files(a, b, c), Some(&with_directive));
    assert!(plan_regions_edit(&directive_plan, &back).is_none());
    // The manifest changed.
    let mut changed = files(a, b, c);
    changed[0].1 = "#define N 4\n#include \"a.dm\"\n#include \"b.dm\"\n#include \"c.dm\"\n";
    assert!(plan_regions_edit(&plan, &Prepared::new(&changed, Some(&first))).is_none());
}
