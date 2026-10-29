//! Independent typed-policy oracle: actual old Engine.scan versus injected native requirement call-site facts.
//! Compares exact findings/ALLOW/notes, not models or full Analyze admission.
use dm_analysis::policy_inputs::{HostCapture, PolicyInputs, PolicyRole};
use dm_preprocess::{SourceProvider, SourceText};
use dq_analyze::{
    captured_raw_policy::Configuration,
    captured_requirement_bool::CapturedRequirementBool,
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
    let names = vec!["requirement_bool".to_string()];
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
    // Explicit fixture-only hierarchy: no production member/ABI completeness claim.
    let mut seed = dm_tree::frontend::EngineSeed {
        identity: 0xdec1,
        symbols: Default::default(),
        hierarchy: dm_tree::EngineHierarchy {
            schema: 0xdec1,
            parents: Vec::new(),
        },
        fields: Arc::from([]),
        intrinsics: Arc::from([]),
    };
    for (child, parent) in [
        ("/", None),
        ("/datum", Some("/")),
        ("/atom", Some("/datum")),
        ("/atom/movable", Some("/atom")),
        ("/obj", Some("/atom/movable")),
        ("/mob", Some("/atom/movable")),
        ("/turf", Some("/atom")),
        ("/area", Some("/atom")),
    ] {
        let child = seed.symbols.intern(child)?;
        let parent = parent.map(|path| seed.symbols.intern(path)).transpose()?;
        seed.hierarchy.parents.push((child, parent));
    }
    let frontend = dm_tree::frontend::build_with_config(
        &root.join("deepquarry.dme"),
        &files,
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
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
    let captured =
        CapturedRequirementBool::capture(&root, &inputs, Configuration::Captured(&config))?;
    let actual = std::iter::once(captured.scan(|| Ok(()))?);
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
        return Err("captured requirement_bool policy differs from old Engine.scan".into());
    }
    let sites = expected
        .values()
        .map(|run| run["sites"].as_array().unwrap().len())
        .sum::<usize>();
    let rules = expected["requirement_bool"]["sites"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|site| site["rule"].as_str())
        .collect::<std::collections::BTreeSet<_>>();
    if rules.len() != 2 {
        return Err(
            format!("seed must exercise both requirement_bool rules, got {rules:?}").into(),
        );
    }

    println!(
        "{}",
        serde_json::json!({"scope":"requirement_bool/explicit-seeded-fixture","lints":expected.len(),"sites":sites,"matched":true,"full_policy_parity":false,"baseline_applied":false})
    );
    Ok(())
}
