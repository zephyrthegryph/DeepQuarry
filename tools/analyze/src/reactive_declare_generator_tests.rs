//! Actual full-frame relation type output against master's generator.
use super::*;
use crate::{captured_declare::BorrowedDeclare, captured_generator_budget::Budget};

#[test]
fn full_native_declare_relation_types_match_current_master() {
    let root = test_scratch::dir("native-declare-relation-types");
    std::fs::create_dir_all(root.join("code/engine/_generated")).unwrap();
    let code = r#"
#if 0
CAPABILITIES(/datum/holder/child)
    ref_one(nameof(inherited), weak = TRUE)
    ref_one(nameof(named_type), type = /datum/alternate)
    ref_one(nameof(explicit), /datum/alternate)
    ref_one(nameof(list_items))
    ref_one(nameof(untyped))
    ref_one(nameof(icon_value))
CAPABILITIES_PART(/datum/holder/child, other_fields)
    owns_one(nameof(part_only))
    owns_one(nameof(inherited))
#endif
/datum/target
/datum/alternate
/datum/holder
    var/datum/target/inherited
    var/list/datum/target/list_items
    var/untyped
    var/icon/icon_value
/datum/holder/child
    var/datum/target/named_type
    var/datum/target/explicit
    var/datum/target/part_only
"#;
    std::fs::write(root.join("code/probe.dm"), code).unwrap();
    std::fs::write(root.join("code/engine/_generated/auto_tracked.dm"), "").unwrap();
    std::fs::write(root.join("deepquarry.dme"), "#include \"code/probe.dm\"\n#include \"code/engine/_generated/auto_tracked.dm\"\n").unwrap();
    let original = Source::capture(&root);
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let queries = Arc::new(Queries::default());
    let settings = queries.clone() as Arc<dyn SettingExpressionQueries>;
    let seed = profile::seed();
    let front = dm_tree::frontend::build_with_executor_and_semantic_state_for_policy_checked(
        &root.join("deepquarry.dme"), &original, &Default::default(),
        dm_tree::frontend::FrontendConfig { workers: 1, engine: Some(&seed), observer: None },
        None, &executor, None, true, &settings,
    ).unwrap().with_body_queries(queries.clone() as Arc<dyn BodySyntaxQueries>);
    let captures = front.files.iter().filter(|file| file.captured).map(|file|
        dm_analysis::policy_inputs::HostCapture::analyze_raw(file.path.clone(), dm_analysis::policy_inputs::PolicyRole::DmSource, file.text.clone()));
    let inputs = dm_analysis::policy_inputs::PolicyInputs::capture(&front, captures).unwrap();
    let raw = crate::captured_raw_policy::CapturedRawPolicy::capture(&root, &inputs,
        crate::captured_raw_policy::Configuration::ProvenMissing).unwrap();
    let budget = Budget::new(64 * 1024 * 1024).unwrap();
    let output = BorrowedDeclare::capture(&raw, &inputs, budget).unwrap().generate(|| Ok(())).unwrap();

    let legacy = crate::run::Engine::new(crate::run::registry(), crate::run::Options {
        root: root.clone(), lints: vec!["sem/keys".to_owned()], ..Default::default()
    }).unwrap();
    let cx = crate::sem::gen::GenCx::new(&legacy.tree, &root);
    let sem = cx.sem().unwrap();
    assert!(sem.errors.is_empty(), "legacy variable fixture errors: {:?}", sem.errors);
    let generator = crate::sem::gen::registry().into_iter().find(|g| g.name() == "declare").unwrap();
    let (expected, _) = crate::sem::gen::render(&*generator, &cx);
    fn relation_body(text: &str) -> &str {
        text.split_once("/proc/declared_rel_var_types()\n").unwrap().1.split_once("#endif\n").unwrap().0
    }
    assert_eq!(relation_body(&output.body), relation_body(&expected));
    assert_eq!(relation_body(&output.body), concat!(
        "\t. = list()\n",
        "\t.[\"/datum/holder/child|inherited\"] = /datum/target\n",
        "\t.[\"/datum/holder/child|named_type\"] = /datum/target\n",
        "\t.[\"/datum/holder/child|part_only\"] = /datum/target\n",
    ));
    assert_eq!(queries.bodies.load(Ordering::Relaxed), 0);
    assert_eq!(queries.compatibility.load(Ordering::Relaxed), 0);
}
