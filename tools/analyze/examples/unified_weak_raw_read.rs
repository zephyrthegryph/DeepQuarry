//! Independent typed-policy oracle: actual old Engine.scan versus injected native declared receiver facts.
//! Compares exact findings/ALLOW/notes, not models or full Analyze admission.
use dm_analysis::policy_inputs::{HostCapture, PolicyInputs, PolicyRole};
use dm_preprocess::{SourceProvider, SourceText};
use dq_analyze::{
    captured_raw_policy::Configuration,
    captured_weak_raw_read::CapturedWeakRawRead,
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
    fn read(&self, _: &Path) -> Result<String, String> {
        Err("oracle requires original acquired bytes".into())
    }
    fn acquired_source(
        &self,
        path: &Path,
    ) -> Result<Option<dm_preprocess::AcquiredSource>, String> {
        if let Some(source) = self.1.borrow().get(path) {
            return Ok(Some(source.clone()));
        }
        // This comes from the same cached FIRST byte read used by raw policy;
        // never certify re-encoded compiler-decoded text as original UTF8.
        let source = dm_preprocess::AcquiredSource::from_original_bytes(self.bytes(path)?, ());
        self.1.borrow_mut().insert(path.into(), source.clone());
        Ok(Some(source))
    }
    fn source_acquisition(
        &self,
        path: &Path,
        text: &SourceText,
    ) -> Option<dm_preprocess::AcquiredSource> {
        self.1
            .borrow()
            .get(path)
            .filter(|source| source.lease().source_text().same_view(text))
            .cloned()
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
    let names = vec!["weak_raw_read".to_string()];
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
    let typed_reference = dq_analyze::sem::sem_for(&old.tree)
        .ok_or("independent old model is unavailable; text fallback cannot certify this fixture")?;
    if !typed_reference.errors.is_empty() {
        return Err(format!(
            "independent old fixture parse errors: {:?}",
            typed_reference.errors
        )
        .into());
    }
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
    let executor =
        dm_exec::BuildExecutor::new(1).map_err(|error| format!("native executor: {error}"))?;
    let frontend = dm_tree::frontend::build_with_executor_and_semantic_state_for_policy(
        &root.join("deepquarry.dme"),
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
        String::from_utf8(files.bytes(&root.join("fixture.toml"))?)?.parse()?;
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
    let captured = CapturedWeakRawRead::capture(&root, &inputs, Configuration::Captured(&config))?;
    let result = captured.scan(|| Ok(()));
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
        return Err("captured weak_raw_read policy differs from old Engine.scan".into());
    }
    let sites = expected
        .values()
        .map(|run| run["sites"].as_array().unwrap().len())
        .sum::<usize>();
    let rules = expected["weak_raw_read"]["sites"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|site| site["rule"].as_str())
        .collect::<std::collections::BTreeSet<_>>();
    let expect_exempt = std::env::args().any(|arg| arg == "--expect-exempt");
    if expect_exempt && (sites != 0 || !String::from_utf8(config.clone())?.contains("exempt_files"))
    {
        return Err("expected an explicitly configured zero-site exemption fixture".into());
    }
    if !expect_exempt && rules.len() != 1 {
        return Err(format!("seed must exercise the raw rule, got {rules:?}").into());
    }

    println!(
        "{}",
        serde_json::json!({"scope":"weak_raw_read/explicit-seeded-fixture","lints":expected.len(),"sites":sites,"matched":true,"full_policy_parity":false,"baseline_applied":false})
    );
    Ok(())
}
