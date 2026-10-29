use super::*;
use crate::policy_inputs::{HostCapture, PolicyRole};
use dm_tree::frontend::{build, ColdFrontend};
use std::sync::Arc;
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
fn frontend(source: &'static str) -> ColdFrontend {
    build(
        Path::new("code/record.dm"),
        &Source(source),
        &Default::default(),
        1,
    )
    .unwrap()
}
fn capture(frontend: &ColdFrontend) -> PolicyInputs {
    let raw = frontend
        .files
        .iter()
        .filter(|file| file.captured)
        .map(|file| {
            let text = if file.text.as_str().contains('\r') {
                file.text
                    .as_str()
                    .replace("\r\n", "\n")
                    .replace('\r', "\n")
                    .into()
            } else {
                file.text.clone()
            };
            HostCapture::analyze_raw(Arc::clone(&file.path), PolicyRole::DmSource, text)
        })
        .collect::<Vec<_>>();
    PolicyInputs::capture(frontend, raw).unwrap()
}
fn prefixes() -> Vec<String> {
    vec!["set_".into(), "get_".into()]
}

#[test]
fn complete_record_rule_retains_exact_existing_site_fields() {
    let inputs = capture(&frontend("/datum/record\n    proc/rebuild()\n        return\n    proc/get_value()\n        return\n    proc/set_value(value)\n        return\n"));
    let rows = findings(&inputs, Path::new("."), &prefixes()).unwrap();
    assert_eq!(
        rows,
        [Finding {
            rule: "records_data_only".into(),
            rel: "code/record.dm".into(),
            line: 2,
            msg: String::new(),
            key: String::new(),
            ident: String::new()
        }]
    );
}

#[test]
fn resolved_accessor_prefix_config_rejudges_without_changing_compiler_capture() {
    let inputs = capture(&frontend("/datum/record\n    proc/custom_read()\n        return\n    proc/get_value()\n        return\n"));
    let revision = inputs.revision();
    assert_eq!(
        findings(&inputs, Path::new("."), &prefixes())
            .unwrap()
            .iter()
            .map(|row| row.line)
            .collect::<Vec<_>>(),
        [2]
    );
    assert_eq!(
        findings(&inputs, Path::new("."), &["custom_".into()])
            .unwrap()
            .iter()
            .map(|row| row.line)
            .collect::<Vec<_>>(),
        [4]
    );
    assert_eq!(inputs.revision(), revision);
}

#[test]
fn record_rule_is_lexical_and_does_not_copy_inherited_bodies() {
    let inputs = capture(&frontend("/datum/record\n    proc/rebuild()\n        return\n/datum/record/child\n/datum/record/overridden\n    rebuild()\n        return\n/datum/other\n    parent_type = /datum/record\n    proc/not_a_record()\n        return\n/datum/recording\n    proc/not_a_record_either()\n        return\n"));
    assert_eq!(
        findings(&inputs, Path::new("."), &prefixes())
            .unwrap()
            .iter()
            .map(|row| row.line)
            .collect::<Vec<_>>(),
        [2, 6]
    );
}

#[test]
fn this_rule_does_not_invent_an_allow_or_path_exemption() {
    let frontend = build(Path::new("code/tests/.hidden/record.dm"), &Source("/datum/record/proc/rebuild() // ALLOW(base_vars): this annotation does not suppress record procs\n    return\n"), &Default::default(),1).unwrap();
    let inputs = capture(&frontend);
    let rows = findings(&inputs, Path::new("."), &prefixes()).unwrap();
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0].rel, "code/tests/.hidden/record.dm");
    assert_eq!(rows[0].line, 1);
}

#[test]
fn missing_analyze_raw_is_an_explicit_error_not_decoded_fallback_or_clean_result() {
    let frontend = frontend("/datum/record/proc/rebuild()\n    return\n");
    let inputs = PolicyInputs::capture(&frontend, []).unwrap();
    let error = findings(&inputs, Path::new("."), &prefixes()).unwrap_err();
    assert!(error.0.contains("MissingView"));
}

#[test]
fn noncompiled_raw_record_text_does_not_become_a_semantic_definition() {
    let frontend = frontend("/datum/record/proc/get_value()\n    return\n");
    let inputs = PolicyInputs::capture(
        &frontend,
        [HostCapture::analyze_raw(
            Arc::new("code/noncompiled.dm".into()),
            PolicyRole::DmSource,
            "/datum/record/proc/injected()\n    return\n"
                .to_owned()
                .into(),
        )],
    )
    .unwrap();
    assert!(findings(&inputs, Path::new("."), &prefixes())
        .unwrap()
        .is_empty());
}

#[test]
fn rule_uses_captured_raw_and_original_line_views_without_filesystem_reads() {
    let inputs = capture(&frontend(
        "/datum/record\r\n    proc/rebuild()\r\n        return\r\n",
    ));
    let rows = findings(&inputs, Path::new("."), &prefixes()).unwrap();
    assert_eq!(rows[0].line, 2);
    assert_eq!(rows[0].rel, "code/record.dm");
}

#[test]
fn named_rule_never_demands_executable_body_syntax() {
    #[derive(Debug)]
    struct NoSyntax;
    impl dm_tree::frontend::BodySyntaxQueries for NoSyntax {
        fn syntax(
            &self,
            _: &Arc<dm_tree::frontend::BodySyntaxInput>,
        ) -> Result<Arc<dm_tree::frontend::BodySyntax>, dm_tree::frontend::Diagnostic> {
            panic!("records_data_only reparsed a body")
        }
    }
    let frontend = frontend("/datum/record/proc/rebuild()\n    return 1\n")
        .with_body_queries(Arc::new(NoSyntax));
    assert_eq!(
        findings(&capture(&frontend), Path::new("."), &prefixes())
            .unwrap()
            .len(),
        1
    );
}

#[cfg(windows)]
#[test]
fn record_report_path_accepts_safe_verbatim_drive_but_not_device_path() {
    let root = Path::new(r"E:\policy-records");
    assert_eq!(relative(root, Path::new(r"\\?\E:\policy-records\code\record.dm")), "code/record.dm");
    assert_ne!(relative(root, Path::new(r"\\.\E:\policy-records\code\record.dm")), "code/record.dm");
}
