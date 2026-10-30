//! Independent typed-policy oracle: actual old Engine.scan versus injected native untyped value/schema facts.
//! Compares exact findings/ALLOW/notes, not models or full Analyze admission.
use dm_analysis::policy_inputs::{HostCapture, PolicyInputs, PolicyRole};
use dm_preprocess::{SourceProvider, SourceText};
use dq_analyze::{
    captured_raw_policy::Configuration,
    captured_untyped::{CapturedUntyped, ManifestRead},
    run::{registry, Engine, Options},
};
use std::{
    cell::RefCell,
    collections::BTreeMap,
    path::{Path, PathBuf},
    sync::Arc,
};
#[derive(Default)]
struct Files(
    RefCell<BTreeMap<PathBuf, Vec<u8>>>,
    RefCell<BTreeMap<PathBuf, dm_preprocess::AcquiredSource>>,
);
impl Files {
    fn bytes(&self, path: &Path) -> Result<Vec<u8>, String> {
        if !self.0.borrow().contains_key(path) {
            self.0.borrow_mut().insert(
                path.into(),
                std::fs::read(path).map_err(|error| error.to_string())?,
            );
        }
        Ok(self.0.borrow()[path].clone())
    }
    fn raw(&self, path: &Path, compiler: Option<&SourceText>) -> Result<SourceText, String> {
        let bytes = self.bytes(path)?;
        let text = String::from_utf8_lossy(&bytes)
            .replace("\r\n", "\n")
            .replace('\r', "\n");
        Ok(match compiler {
            Some(native) if native.as_str() == text => native.clone(),
            _ => text.into(),
        })
    }
}
impl SourceProvider for Files {
    fn acquired_source(
        &self,
        path: &Path,
    ) -> Result<Option<dm_preprocess::AcquiredSource>, String> {
        if !self.1.borrow().contains_key(path) {
            let bytes = self.bytes(path)?;
            self.1.borrow_mut().insert(
                path.into(),
                dm_preprocess::AcquiredSource::from_original_slice(&bytes, ()),
            );
        }
        Ok(self.1.borrow().get(path).cloned())
    }
    fn source_acquisition(
        &self,
        path: &Path,
        text: &SourceText,
    ) -> Option<dm_preprocess::AcquiredSource> {
        self.1
            .borrow()
            .get(path)
            .filter(|a| a.lease().source_text().same_view(text))
            .cloned()
    }

    fn read(&self, path: &Path) -> Result<String, String> {
        Ok(dm_preprocess::decode_source_bytes(&self.bytes(path)?))
    }
}
#[path = "../../dmb/crates/dm-analysis/examples/support/reference_hierarchy.rs"]
mod reference_hierarchy;
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let root = PathBuf::from(
        std::env::args()
            .nth(1)
            .ok_or("expected explicit fixture root")?,
    );
    let root = if root.is_absolute() {
        root
    } else {
        std::env::current_dir()?.join(root)
    };
    let mut args = std::env::args().skip(2);
    let mut project = None;
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--project" => {
                project = Some(args.next().ok_or("--project requires a manifest")?);
            }
            "--expect-unsupported" | "--expect-empty" => (),
            _ if !arg.starts_with('-') && project.is_none() => project = Some(arg),
            _ => return Err(format!("unknown fixture option {arg}").into()),
        }
    }
    let names = vec!["untyped".to_string()];
    // The old Engine owns its unchanged filesystem discovery, views and scan path.
    // It never shares a semantic model or raw source roster with the native side.
    let old = Engine::new(
        registry(),
        Options {
            root: root.clone(),
            scopes_from: Some(root.clone()),
            lints: names.clone(),
            raw: true,
            no_cache: true,
            ..Default::default()
        },
    )?;
    let _typed_reference = dq_analyze::sem::sem_for(&old.tree)
        .ok_or("independent old model is unavailable; text fallback cannot certify this fixture")?;
    let mut expected = BTreeMap::new();
    for name in &names {
        let lint = old.reg.find(name).ok_or("old lint missing")?;
        let (run, allow, _) = old.scan(lint);
        expected.insert(
            name.clone(),
            serde_json::json!({"sites":run.sites,"allow_used":allow,"notes":run.notes}),
        );
    }
    let files = Files::default();
    let seed = reference_hierarchy::seed();
    let executor = dm_exec::BuildExecutor::new(1).map_err(|e| format!("native executor: {e:?}"))?;
    let frontend = dm_tree::frontend::build_with_executor_and_semantic_state_for_policy(
        &root.join(project.as_deref().unwrap_or("deepquarry.dme")),
        &files,
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
        None,
        &executor,
        None,
        true,
    )
    .map_err(|e| format!("native fixture failed: {e:?}"))?;
    let mut captures = Vec::new();
    for file in frontend.files.iter().filter(|file| file.captured) {
        captures.push(HostCapture::analyze_raw(
            Arc::clone(&file.path),
            PolicyRole::DmSource,
            files.raw(&file.path, Some(&file.text))?,
        ));
    }
    let roster: toml::Value =
        String::from_utf8(files.bytes(&root.join("raw_inputs.toml"))?)?.parse()?;
    for name in roster
        .get("sources")
        .and_then(toml::Value::as_array)
        .ok_or("explicit raw source roster missing")?
    {
        let path = root.join(name.as_str().ok_or("raw roster member is not text")?);
        let compiled = frontend
            .files
            .iter()
            .find(|file| file.path.as_ref() == &path && file.captured)
            .map(|file| &file.text);
        captures.push(HostCapture::analyze_raw(
            Arc::new(path.clone()),
            PolicyRole::DmSource,
            files.raw(&path, compiled)?,
        ));
    }
    let inputs = PolicyInputs::capture(&frontend, captures)?;
    let config = files.bytes(&root.join("tools/ci/lint_scopes.toml"))?;
    let captured = CapturedUntyped::capture(&root, &inputs, Configuration::Captured(&config))?;
    let input = dm_analysis::value_query::ArchiveValueInput::new(Arc::clone(inputs.archive()), &[]);
    let proof = input.compute()?; // Standalone independent oracle only; host uses same QueryDb proof.
    let manifest_path = root.join("deepquarry.dme");
    let compiled_manifest = inputs.mapping().source_acquisitions().any(|(path, _)| {
        dm_preprocess::regions::canonical_path(path)
            == dm_preprocess::regions::canonical_path(&manifest_path)
    });
    let original_manifest = if compiled_manifest || !manifest_path.try_exists()? {
        None
    } else {
        Some(files.bytes(&manifest_path)?)
    };
    let manifest = if compiled_manifest {
        ManifestRead::Compiled
    } else if let Some(bytes) = original_manifest.as_deref() {
        ManifestRead::OriginalBytes(bytes)
    } else {
        ManifestRead::ProvenUnavailable
    };
    let original_body_count = input.archive().occurrences().len();
    let source_variable_count = input
        .archive()
        .tree()
        .members()
        .iter()
        .filter(|member| {
            member.kind == dm_tree::MemberKind::Var
                && member.definition == dm_tree::DefinitionMode::Declare
        })
        .count();
    let compiled_source_count = inputs
        .files()
        .filter(|file| file.is_compiled() && file.role() == PolicyRole::DmSource)
        .count();
    let mut native_checkpoints = 0usize;
    let result = captured.scan(&input, proof, manifest, || {
        native_checkpoints += 1;
        Ok(())
    });
    if std::env::args().any(|arg| arg == "--expect-unsupported") {
        let reference_sites = expected
            .values()
            .map(|run| run["sites"].as_array().unwrap().len())
            .sum::<usize>();
        if reference_sites == 0 {
            return Err("negative fixture requires actual old policy findings".into());
        }
        let error = result
            .err()
            .ok_or("native policy falsely accepted unsupported checker qualifiers")?;
        println!(
            "{}",
            serde_json::json!({"scope":"checker-qualifier/explicit-unsupported","reference_sites":reference_sites,"native_findings_emitted":false,"refusal":error,"full_policy_parity":false})
        );
        return Ok(());
    }
    let actual = std::iter::once(result?);
    let mut observed = BTreeMap::new();
    for result in actual {
        observed.insert(result.name,serde_json::json!({"sites":result.run.sites,"allow_used":result.allow_used,"notes":result.run.notes}));
    }
    if expected != observed {
        eprintln!(
            "{}",
            serde_json::to_string_pretty(
                &serde_json::json!({"reference":expected,"native":observed})
            )?
        );
        return Err("captured untyped policy differs from old Engine.scan".into());
    }
    let sites = expected
        .values()
        .map(|run| run["sites"].as_array().unwrap().len())
        .sum::<usize>();
    let rules = expected["untyped"]["sites"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|site| site["rule"].as_str())
        .collect::<std::collections::BTreeSet<_>>();
    let expect_empty = std::env::args().any(|arg| arg == "--expect-empty");
    if expect_empty {
        if sites != 0
            || original_body_count == 0
            || source_variable_count == 0
            || compiled_source_count == 0
            || native_checkpoints == 0
        {
            return Err("empty oracle requires exact old/native zero after genuine original body/source/value work".into());
        }
        // An empty comparison is not an exemption escape hatch. Allow only
        // absent or explicitly empty list configuration for this lint.
        let settings: toml::Value = std::str::from_utf8(&config)?.parse()?;
        if let Some(section) = settings.get("lint").and_then(|v| v.get("untyped")) {
            let table = section
                .as_table()
                .ok_or("empty oracle requires untyped table configuration")?;
            for (key, value) in table {
                if key != "lists" {
                    return Err(
                        "empty oracle disallows non-list untyped scope configuration".into(),
                    );
                }
                for value in value
                    .as_table()
                    .ok_or("empty oracle requires list table")?
                    .values()
                {
                    if !value.as_array().is_some_and(|values| values.is_empty()) {
                        return Err("empty oracle disallows nonempty exemption/schema lists".into());
                    }
                }
            }
        }
    } else if sites == 0 {
        return Err("positive fixture requires actual independent old findings".into());
    }
    if let Some(required) = roster.get("required_rules").and_then(toml::Value::as_array) {
        let required = required
            .iter()
            .map(|v| v.as_str().ok_or("required rule must be text"))
            .collect::<Result<std::collections::BTreeSet<_>, _>>()?;
        if rules != required {
            return Err(
                format!("seed must exercise declared rules {required:?}, got {rules:?}").into(),
            );
        }
    }

    println!(
        "{}",
        serde_json::json!({"scope":"untyped/explicit-seeded-fixture","lints":expected.len(),"sites":sites,"matched":true,"expected_empty":expect_empty,"original_body_count":original_body_count,"source_variable_count":source_variable_count,"compiled_source_count":compiled_source_count,"native_checkpoints":native_checkpoints,"native_value_proof_computed":true,"full_policy_parity":false,"baseline_applied":false})
    );
    Ok(())
}
