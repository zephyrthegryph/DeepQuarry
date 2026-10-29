use super::*;
use dm_analysis::policy_inputs::{HostCapture, PolicyRole};
use std::sync::Arc;
struct Source(dm_preprocess::AcquiredSource);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Err("policy test requires actual acquired bytes".into())
    }
    fn acquired_source(&self, _: &Path) -> Result<Option<dm_preprocess::AcquiredSource>, String> {
        Ok(Some(self.0.clone()))
    }
    fn source_acquisition(
        &self,
        _: &Path,
        text: &dm_preprocess::SourceText,
    ) -> Option<dm_preprocess::AcquiredSource> {
        self.0
            .lease()
            .source_text()
            .same_view(text)
            .then(|| self.0.clone())
    }
}
fn inputs(source: &'static str, uncompiled: bool) -> (std::path::PathBuf, PolicyInputs) {
    let root = std::env::current_dir()
        .unwrap()
        .join("requirement-bool-fixture");
    let provider = Source(dm_preprocess::AcquiredSource::from_original_bytes(
        source.as_bytes().to_vec(),
        (),
    ));
    let frontend = dm_tree::frontend::build(
        &root.join("code/probe.dm"),
        &provider,
        &Default::default(),
        1,
    )
    .unwrap();
    let mut raw = frontend
        .files
        .iter()
        .filter(|f| f.captured)
        .map(|f| {
            HostCapture::analyze_raw(Arc::clone(&f.path), PolicyRole::DmSource, f.text.clone())
        })
        .collect::<Vec<_>>();
    if uncompiled {
        raw.push(HostCapture::analyze_raw(
            Arc::new(root.join("code/uncompiled.dm")),
            PolicyRole::DmSource,
            "#define LEFTOVER(x) req_bool(x)\n".to_string().into(),
        ));
    }
    (root, PolicyInputs::capture(&frontend, raw).unwrap())
}
#[test]
fn full_union_preserves_macro_invocations_uncompiled_raw_rows_and_retired_names() {
    let(root,input)=inputs("/proc/req_bool(value)\n    return value\n#define WRAPPED(x) req_bool(x)\n/proc/probe(holder)\n    var/a = WRAPPED(1)\n    holder.req_bool(2)\n    return\n    WRAPPED(3)\n#define REQ_TAG(x) x\n",true);
    let config = b"[lint.requirement_bool.lists]\nretired_macros=['REQ_TAG']\n";
    let run = CapturedRequirementBool::capture(&root, &input, Configuration::Captured(config))
        .unwrap()
        .scan(|| Ok(()))
        .unwrap();
    assert_eq!(
        run.run
            .sites
            .iter()
            .map(|s| (s.rule.as_str(), s.rel.as_str(), s.line))
            .collect::<Vec<_>>(),
        [
            ("boolean_callback", "code/probe.dm", 1),
            ("boolean_callback", "code/probe.dm", 3),
            ("boolean_callback", "code/probe.dm", 5),
            ("boolean_callback", "code/probe.dm", 8),
            ("boolean_callback", "code/uncompiled.dm", 1),
            ("legacy_macro", "code/probe.dm", 9),
        ]
    );
    assert!(run.allow_used.is_empty());
    assert!(run.run.notes.is_empty());
    assert!(run
        .run
        .sites
        .iter()
        .all(|site| site.msg.is_empty() && site.key.is_empty() && site.ident.is_empty()));
}
#[test]
fn unsupported_or_cancelled_body_cannot_return_a_clean_partial_lint() {
    let (root, input) = inputs("/proc/probe()\n    totally_bad @@ syntax\n", false);
    let policy =
        CapturedRequirementBool::capture(&root, &input, Configuration::ProvenMissing).unwrap();
    assert!(policy.scan(|| Ok(())).is_err());
    assert!(policy.scan(|| Err("cancelled".into())).is_err());
}
