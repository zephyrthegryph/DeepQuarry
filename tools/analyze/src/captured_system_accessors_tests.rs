use super::*;
use dm_analysis::policy_inputs::{HostCapture, PolicyRole};
use dm_preprocess::SourceProvider;
use std::{cell::RefCell, collections::BTreeMap, path::PathBuf, sync::Arc};
struct Original {
    bytes: BTreeMap<PathBuf, Vec<u8>>,
    acquired: RefCell<BTreeMap<PathBuf, dm_preprocess::AcquiredSource>>,
}
impl dm_preprocess::SourceProvider for Original {
    fn read(&self, _: &Path) -> Result<String, String> {
        Err("must use original acquired bytes".into())
    }
    fn acquired_source(&self, p: &Path) -> Result<Option<dm_preprocess::AcquiredSource>, String> {
        if !self.acquired.borrow().contains_key(p) {
            let bytes = self
                .bytes
                .get(p)
                .ok_or("missing original fixture file")?
                .clone();
            self.acquired.borrow_mut().insert(
                p.into(),
                dm_preprocess::AcquiredSource::from_original_bytes(bytes, ()),
            );
        }
        Ok(self.acquired.borrow().get(p).cloned())
    }
    fn source_acquisition(
        &self,
        p: &Path,
        t: &dm_preprocess::SourceText,
    ) -> Option<dm_preprocess::AcquiredSource> {
        self.acquired
            .borrow()
            .get(p)
            .filter(|s| s.lease().source_text().same_view(t))
            .cloned()
    }
}
fn inputs(extra: &[(&str, &str)], raw: bool) -> (PathBuf, PolicyInputs) {
    let root = std::env::current_dir()
        .unwrap()
        .join("native-system-accessor-generator-unit");
    let manifest = root.join("deepquarry.dme");
    let provider = Original {
        bytes: std::iter::once((manifest.clone(), b"/datum\n".to_vec()))
            .chain(
                extra
                    .iter()
                    .map(|(rel, text)| (root.join(rel), text.as_bytes().to_vec())),
            )
            .collect(),
        acquired: Default::default(),
    };
    let frontend = dm_tree::frontend::build(&manifest, &provider, &Default::default(), 1).unwrap();
    // The original provider issues the manifest acquisition used by include_order;
    // AnalyzeRaw must be separately present even when compiler bytes are equal.
    let manifest_source = provider.acquired_source(&manifest).unwrap().unwrap();
    let mut captures = vec![HostCapture::analyze_raw(
        Arc::new(manifest.clone()),
        PolicyRole::DmSource,
        manifest_source.lease().source_text().clone(),
    )];
    if raw {
        for (rel, _) in extra {
            let path = root.join(rel);
            let source = provider.acquired_source(&path).unwrap().unwrap();
            captures.push(HostCapture::analyze_raw(
                Arc::new(path),
                PolicyRole::DmSource,
                source.lease().source_text().clone(),
            ));
        }
    }
    (root, PolicyInputs::capture(&frontend, captures).unwrap())
}

#[test]
fn whole_system_accessors_preserves_own_fields_inactive_source_and_guards() {
    let(root,inputs)=inputs(&[("code/a.dm", "/datum/system/power\n\tvar/own\n#if 0\n/datum/system/power\n\tvar/inactive\n#endif\nSYSTEM_DEF(power)\n\tvar\n\t\tgrouped\nSYSTEM_ACCESSOR(power, power_own, nameof(own))\nSYSTEM_ACCESSOR(power, power_inactive, nameof(inactive), /datum)\nSYSTEM_ACCESSOR(power, power_grouped, nameof(grouped))\n"),("code/tests/b.dm","SYSTEM_ACCESSOR(power, test_own, nameof(own))\n"),("code/.hidden.dm","SYSTEM_ACCESSOR(power, hidden, nameof(own))\n")],true);
    let out = CapturedSystemAccessors::capture(&root, inputs.archive(), &inputs)
        .unwrap()
        .generate(|| Ok(()))
        .unwrap();
    assert!(out.diags.is_empty(), "{:?}", out.diags);
    assert!(out.body.contains("/proc/power_own()"));
    assert!(out.body.contains("return SSpower?.own"));
    assert!(out.body.contains("/proc/power_inactive() as /datum"));
    assert!(out.body.contains("/proc/power_grouped()"));
    assert!(out.body.contains(crate::generator_test_scope::TEST_GUARD));
    assert!(!out.body.contains("/proc/hidden"));
    assert!(!FULL_WORKSPACE_COVERAGE);
}
#[test]
fn exact_selector_does_not_make_macro_only_or_inherited_fields_owned() {
    let(root,inputs)=inputs(&[("code/a.dm","SYSTEM_DEF(macro_only)\n\tvar/v\n/datum/system/base\n\tvar/inherited\n/datum/system/base/child\n\tvar/own\nSYSTEM_ACCESSOR(macro_only, missing, nameof(v))\nSYSTEM_ACCESSOR(base/child, wrong, nameof(inherited))\nSYSTEM_ACCESSOR(base/child, yes, nameof(own))\n")],true);
    let out = CapturedSystemAccessors::capture(&root, inputs.archive(), &inputs)
        .unwrap()
        .generate(|| Ok(()))
        .unwrap();
    assert_eq!(out.diags.len(), 2, "{:?}", out.diags);
    assert!(out.body.contains("/proc/yes()"));
    assert!(!out.body.contains("/proc/wrong()"));
}
#[test]
fn malformed_and_duplicates_keep_original_diagnostic_order_and_winner() {
    let(root,inputs)=inputs(&[("code/a.dm","/datum/system/x\n\tvar/v\nSYSTEM_ACCESSOR(x)\nSYSTEM_ACCESSOR(x, raw, v)\nSYSTEM_ACCESSOR(x, bad_type, nameof(v), bad)\nSYSTEM_ACCESSOR(x, same, nameof(v))\nSYSTEM_ACCESSOR(x, same, nameof(v), /datum)\n")],true);
    let out = CapturedSystemAccessors::capture(&root, inputs.archive(), &inputs)
        .unwrap()
        .generate(|| Ok(()))
        .unwrap();
    assert_eq!(
        out.diags.iter().map(|d| d.line).collect::<Vec<_>>(),
        [3, 4, 5, 7]
    );
    assert_eq!(out.body.matches("/proc/same()").count(), 1);
    assert!(!out.body.contains("/proc/same() as"));
}
#[test]
fn foreign_archive_and_cancelled_empty_generator_never_publish_clean_output() {
    let (root, a) = inputs(&[], true);
    let (_, b) = inputs(&[], true);
    assert!(CapturedSystemAccessors::capture(&root, b.archive(), &a).is_err());
    assert!(CapturedSystemAccessors::capture(&root, a.archive(), &a)
        .unwrap()
        .generate(|| Err("cancelled".into()))
        .unwrap_err()
        .contains("cancelled"));
    assert!(CapturedSystemAccessors::capture(&root.join("wrong"), a.archive(), &a).is_err());
}
#[test]
fn original_type_var_visitor_preserves_grouped_fields_and_does_not_inherit() {
    let mut pairs = Vec::new();
    crate::raw_type_vars_policy::visit(
        "/datum/system/x\n\tvar\n\t\tlist/a\n\t\tb\n/datum/system/x/child\n\tvar/c\n",
        |t, v| pairs.push((t.to_owned(), v.to_owned())),
    );
    assert_eq!(
        pairs,
        [
            ("/datum/system/x".into(), "a".into()),
            ("/datum/system/x".into(), "b".into()),
            ("/datum/system/x/child".into(), "c".into())
        ]
    );
}

#[test]
fn compiled_code_without_original_raw_capture_is_explicitly_unsupported() {
    let root = std::env::current_dir()
        .unwrap()
        .join("native-system-accessor-generator-missing-view");
    let manifest = root.join("deepquarry.dme");
    let provider = Original {
        bytes: BTreeMap::from([
            (manifest.clone(), b"#include \"code/a.dm\"\n".to_vec()),
            (root.join("code/a.dm"), b"/datum/example\n".to_vec()),
        ]),
        acquired: Default::default(),
    };
    let frontend = dm_tree::frontend::build(&manifest, &provider, &Default::default(), 1).unwrap();
    // Admit the real manifest view, deliberately omit only the included DM view.
    let manifest_source = provider.acquired_source(&manifest).unwrap().unwrap();
    let inputs = PolicyInputs::capture(
        &frontend,
        [HostCapture::analyze_raw(
            Arc::new(manifest.clone()),
            PolicyRole::DmSource,
            manifest_source.lease().source_text().clone(),
        )],
    )
    .unwrap();
    let error = CapturedSystemAccessors::capture(&root, inputs.archive(), &inputs)
        .err()
        .expect("missing original included raw view must refuse at capture");
    assert!(
        error.contains("AnalyzeRaw") && error.contains("a.dm"),
        "{error}"
    );
}

#[test]
fn marker_limit_refuses_instead_of_returning_partial_generator_output() {
    let text = "SYSTEM_ACCESSOR(x)\n".repeat(crate::captured_raw_policy::MAX_FIXTURE_SITES + 1);
    let (root, inputs) = inputs(&[("code/a.dm", &text)], true);
    let error = CapturedSystemAccessors::capture(&root, inputs.archive(), &inputs)
        .unwrap()
        .generate(|| Ok(()))
        .unwrap_err();
    assert!(error.contains("marker budget"), "{error}");
}
#[test]
fn cancelled_membership_walk_does_not_publish_partial_accessors() {
    let (root, inputs) = inputs(
        &[(
            "code/a.dm",
            "/datum/system/x\n\tvar/v\nSYSTEM_ACCESSOR(x, okay, nameof(v))\n",
        )],
        true,
    );
    let mut checks = 0;
    let result = CapturedSystemAccessors::capture(&root, inputs.archive(), &inputs)
        .unwrap()
        .generate(|| {
            checks += 1;
            if checks >= 6 {
                Err("cancelled during original views".into())
            } else {
                Ok(())
            }
        });
    assert!(result.unwrap_err().contains("cancelled"));
}
