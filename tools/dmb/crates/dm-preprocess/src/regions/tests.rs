use super::*;

struct Memory(BTreeMap<PathBuf, String>);

impl SourceProvider for Memory {
    fn read(&self, path: &Path) -> Result<String, String> {
        self.0.get(path).cloned().ok_or_else(|| "missing".into())
    }
}

fn fixture(files: &[(&str, &str)]) -> DirectivePlan {
    let provider = Memory(
        files
            .iter()
            .map(|(path, text)| (PathBuf::from(path), (*text).to_owned()))
            .collect(),
    );
    plan_regions(Path::new("project.dme"), &provider, &BTreeMap::new())
}

#[test]
fn native_boolean_macros_follow_define_undef_and_caller_precedence() {
    let provider = Memory(BTreeMap::from([(PathBuf::from("project.dme"),
        "var/a = TRUE + FALSE\n#undef TRUE\nvar/b = TRUE\n#define TRUE 7\nvar/c = TRUE\n#undef FALSE\n#define FALSE 9\nvar/d = FALSE\n".into())]));
    let plan = plan_regions(Path::new("project.dme"), &provider, &BTreeMap::new());
    let expanded = expand_regions_text(&plan, 2);
    assert!(expanded.diagnostics.is_empty());
    assert_eq!(
        expanded.text.as_ref(),
        "var/a = 1 + 0\nvar/b = TRUE\nvar/c = 7\nvar/d = 9\n"
    );
    let caller = BTreeMap::from([("TRUE".into(), "3".into()), ("FALSE".into(), "4".into())]);
    let plan = plan_regions(Path::new("project.dme"), &provider, &caller);
    assert!(expand_regions_text(&plan, 1)
        .text
        .starts_with("var/a = 3 + 4\n"));
}

#[test]
fn native_vision_macros_preserve_undef_shadow_and_caller_precedence() {
    let provider = Memory(BTreeMap::from([(PathBuf::from("project.dme"),
        "var/a = SEE_BLACKNESS | SEE_INFRA | SEE_MOBS | SEE_OBJS | SEE_PIXELS | SEE_SELF | SEE_THRU | SEE_TURFS\n#undef SEE_BLACKNESS\nvar/b = SEE_BLACKNESS\n/datum/shadow\n    var/SEE_BLACKNESS = 9\n#define SEE_BLACKNESS 7\nvar/c = SEE_BLACKNESS\n".into())]));
    let plan = plan_regions(Path::new("project.dme"), &provider, &BTreeMap::new());
    for workers in [1, 2] {
        let expanded = expand_regions_text(&plan, workers);
        assert!(expanded.diagnostics.is_empty());
        assert_eq!(expanded.text.as_ref(),
            "var/a = 1024 | 64 | 4 | 8 | 256 | 32 | 512 | 16\nvar/b = SEE_BLACKNESS\n/datum/shadow\n    var/SEE_BLACKNESS = 9\nvar/c = 7\n");
    }
    let caller = BTreeMap::from([("SEE_BLACKNESS".into(), "11".into())]);
    let plan = plan_regions(Path::new("project.dme"), &provider, &caller);
    assert!(expand_regions_text(&plan, 1).text.starts_with("var/a = 11 | 64"));
}

#[test]
fn child_effects_split_parent_and_parallel_schedule_preserves_output() {
    let plan = fixture(&[
        ("project.dme", "#include \"parent.dm\"\n"),
        (
            "parent.dm",
            "#define VALUE 1\nvar/before = VALUE\n#include \"child.dm\"\nvar/after = VALUE\n",
        ),
        ("child.dm", "#define VALUE 2\nvar/child = VALUE\n"),
    ]);
    let serial = expand_regions(&plan, 1);
    let parallel = expand_regions(&plan, 4);
    assert!(serial.diagnostics.is_empty());
    assert_eq!(
        serial.text.as_ref(),
        "var/before = 1\nvar/child = 2\nvar/after = 2\n"
    );
    assert_eq!(serial.text.as_ref(), parallel.text.as_ref());
    assert_eq!(serial.tokens, parallel.tokens);
    assert_eq!(serial.origins[2].origin.source_line, 4);
    assert_eq!(
        serial.origins[1].origin.path.as_path(),
        Path::new("child.dm")
    );
}

#[test]
fn repeated_text_file_suppresses_both_tokens_and_directive_effects() {
    let plan = fixture(&[
        (
            "project.dme",
            "#define VALUE 1\n#include \"body.dm\"\n#define VALUE 2\n#include \"body.dm\"\n",
        ),
        (
            "body.dm",
            "#if VALUE == 1\n#define SAW_ONE 1\nvar/first = VALUE\n#else\n#define SAW_TWO 1\nvar/second = VALUE\n#endif\n",
        ),
    ]);
    assert!(plan.occurrences[2].suppressed);
    assert!(plan.final_macros.contains_key("SAW_ONE"));
    assert!(!plan.final_macros.contains_key("SAW_TWO"));
    assert_eq!(expand_regions(&plan, 2).text.as_ref(), "var/first = 1\n");
}

#[test]
fn manifest_grammar_encounter_and_declaration_emission_orders_are_separate() {
    let plan = fixture(&[
        (
            "project.dme",
            "#define VALUE 1\nvar/manifest = VALUE\n#include \"body.dm\"\nvar/manifest_after = VALUE\n",
        ),
        ("body.dm", "#define VALUE 2\nvar/body = VALUE\n"),
    ]);
    assert_eq!(
        expand_regions(&plan, 2).text.as_ref(),
        "var/manifest = 1\nvar/body = 2\nvar/manifest_after = 2\n"
    );
    let order: Vec<_> = plan.emission_regions().collect();
    assert!(plan.regions[order[0]].manifest_source);
    assert!(order.windows(2).all(|pair| {
        plan.regions[pair[0]].encounter_ordinal < plan.regions[pair[1]].encounter_ordinal
    }));
}

#[test]
fn included_members_keep_manifest_type_context_in_the_grammar_stream() {
    let plan = fixture(&[
        (
            "project.dme",
            "/datum/a\n#include \"a.dm\"\n/datum/b\n#include \"b.dm\"\n",
        ),
        (
            "a.dm",
            "    var/file_value = __FILE__\n    var/line_value = __LINE__\n",
        ),
        (
            "b.dm",
            "    var/file_value = __FILE__\n    var/line_value = __LINE__\n",
        ),
    ]);
    let output = expand_regions(&plan, 2);
    let ast = dm_syntax::parse(&output.text);
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    assert_eq!(ast.items.len(), 2);
    assert_eq!(ast.items[0].children.len(), 2);
    assert_eq!(ast.items[1].children.len(), 2);
    assert!(output.text.contains("var/file_value = \"a.dm\""));
    assert!(output.text.contains("var/line_value = 2"));
}

#[test]
fn actual_macro_expansions_retain_definition_and_replacement_ancestry() {
    let plan = fixture(&[
        ("project.dme", "#include \"body.dm\"\n"),
        (
            "body.dm",
            "#define INNER 7\n#define OUTER INNER\nvar/value = OUTER\n",
        ),
    ]);
    let output = expand_regions(&plan, 2);
    let trace = &output.origins[0].macro_expansions;
    assert_eq!(trace.len(), 2);
    assert_eq!(trace[0].name, "OUTER");
    assert_eq!(trace[0].definition.as_ref().unwrap().source_line, 2);
    assert_eq!(trace[1].name, "INNER");
    assert_eq!(trace[1].definition.as_ref().unwrap().source_line, 1);
    assert_eq!(trace[1].replacement_chain, vec!["OUTER"]);
}

#[test]
fn expansion_and_directive_diagnostics_are_merged_in_encounter_order() {
    let plan = fixture(&[
        ("project.dme", "#include \"parent.dm\"\n"),
        (
            "parent.dm",
            "#define F(x) x\nvar/bad = F(1,2)\n#error first\n#include \"child.dm\"\n#error last\n",
        ),
        ("child.dm", "#error child\n"),
    ]);
    let output = expand_regions(&plan, 2);
    assert_eq!(output.diagnostics.len(), 4);
    assert!(output.diagnostics[0].message.contains("expects"));
    assert_eq!(output.diagnostics[1].message, "first");
    assert_eq!(output.diagnostics[2].message, "child");
    assert_eq!(output.diagnostics[3].message, "last");
}

#[test]
fn terminal_file_dir_and_nontext_items_are_separate_from_text() {
    let plan = fixture(&[
        (
            "project.dme",
            "#define FILE_DIR \"early\"\n#include \"child.dm\"\n#undef FILE_DIR\n#if 0\n#include \"missing.dm\"\n#include \"missing.dmm\"\n#endif\n#include \"world.dmm\"\n#include \"skin.dmf\"\n",
        ),
        ("child.dm", "#define FILE_DIR \"late\"\nvar/asset = 'asset.txt'\n"),
    ]);
    assert!(plan.diagnostics.is_empty());
    assert_eq!(plan.file_dirs, vec![PathBuf::from("early")]);
    assert_eq!(plan.final_macros["FILE_DIR"].replacement, "\"early\"");
    assert_eq!(
        plan.non_text(NonTextKind::Map).collect::<Vec<_>>(),
        vec![Path::new("world.dmm")]
    );
    assert_eq!(
        plan.non_text(NonTextKind::Skin).collect::<Vec<_>>(),
        vec![Path::new("skin.dmf")]
    );
    assert!(!plan.dependencies.contains(Path::new("missing.dm")));
    assert_eq!(expand_regions(&plan, 2).text.as_ref(), "var/asset = 'asset.txt'\n");
}

#[test]
fn conditions_remain_in_the_parent_and_joined_tokens_keep_indentation() {
    let plan = fixture(&[
        ("project.dme", "#include \"parent.dm\"\n"),
        (
            "parent.dm",
            "#define ENABLE 1\n#if ENABLE\n/datum/sample\n#include \"members.dm\"\nvar/after = ENABLE\n#endif\n",
        ),
        ("members.dm", "#define ENABLE 2\n    var/value = __LINE__\n"),
    ]);
    let output = expand_regions(&plan, 2);
    assert!(output.diagnostics.is_empty());
    assert_eq!(
        output.text.as_ref(),
        "/datum/sample\n    var/value = 2\nvar/after = 2\n"
    );
}

#[test]
fn canonical_paths_preserve_unresolved_parent_components() {
    assert_eq!(
        canonical_path(Path::new("../a/../b.dm")),
        Path::new("../b.dm")
    );
    assert_eq!(
        canonical_path(Path::new("a/./b/../c.dm")),
        Path::new("a/c.dm")
    );
}

#[test]
fn captured_paths_probe_parses_with_its_observed_type_member_context() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../fixtures/phase0/preprocess/paths-origins/phase0_runtime.dme");
    let plan = plan_regions(&root, &crate::FileSystem, &BTreeMap::new());
    let output = expand_regions(&plan, 2);
    assert!(output.diagnostics.is_empty(), "{:?}", output.diagnostics);
    let ast = dm_syntax::parse(&output.text);
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    let a = ast
        .items
        .iter()
        .find(|item| item.header == "/datum/a")
        .unwrap();
    let b = ast
        .items
        .iter()
        .find(|item| item.header == "/datum/b")
        .unwrap();
    assert_eq!(a.children[0].header, "var/file_value = \"a/../a/body.dm\"");
    assert_eq!(b.children[0].header, "var/file_value = \"b/body.dm\"");
    assert_eq!(a.children[1].header, "var/line_value = 2");
    assert_eq!(b.children[1].header, "var/line_value = 2");
}

#[test]
fn captured_deferred_probe_retains_encounter_values_and_emission_projection() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../fixtures/phase0/preprocess/deferred-manifest/phase0_runtime.dme");
    let plan = plan_regions(&root, &crate::FileSystem, &BTreeMap::new());
    let output = expand_regions(&plan, 2);
    assert!(output.diagnostics.is_empty(), "{:?}", output.diagnostics);
    let ast = dm_syntax::parse(&output.text);
    assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
    for (header, value) in [
        ("/world/proc/late()", 2),
        ("/proc/second()", 3),
        ("/proc/early()", 1),
    ] {
        let item = ast.items.iter().find(|item| item.header == header).unwrap();
        assert_eq!(item.children[0].header, format!("return {value}"));
    }
    let procedures: Vec<_> = output
        .emission_regions
        .iter()
        .flat_map(|index| {
            plan.regions[*index]
                .segments
                .iter()
                .flat_map(|segment| segment.lines.iter())
                .filter_map(|line| {
                    let text = line.text.trim();
                    matches!(
                        text,
                        "/world/proc/late()" | "/proc/second()" | "/proc/early()"
                    )
                    .then_some(text)
                })
        })
        .collect();
    assert_eq!(
        procedures,
        vec!["/world/proc/late()", "/proc/second()", "/proc/early()"]
    );
}

#[test]
fn persistent_full_environments_keep_token_paste_and_definition_epochs_exact() {
    let plan=fixture(&[("project.dme","#define CAT(a,b) a##b\n#define VALUE1 11\nvar/a = CAT(VALUE,1)\n#define VALUE1 22\nvar/b = CAT(VALUE,1)\n#undef VALUE1\nvar/c = CAT(VALUE,1)\n")]);
    let result = expand_regions(&plan, 2);
    assert!(result.diagnostics.is_empty(), "{:?}", result.diagnostics);
    assert_eq!(result.text.as_ref(), "var/a = 11\nvar/b = 22\nvar/c = VALUE1\n");
    let origins = result
        .origins
        .iter()
        .take(2)
        .map(|origin| {
            origin
                .macro_expansions
                .iter()
                .find(|expansion| expansion.name == "VALUE1")
                .unwrap()
                .definition
                .as_ref()
                .unwrap()
                .source_line
        })
        .collect::<Vec<_>>();
    assert_eq!(origins, vec![2, 4]);
}
