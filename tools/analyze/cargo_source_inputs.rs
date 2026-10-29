//! Source closure for build/cache identity. TOML is parsed, never grepped.
//! Optional/target/dev/build local dependencies are conservatively included.
//! Local include/build inputs outside path-package roots must be declared in
//! package/workspace.metadata.dq-source-key.inputs. Arbitrary undeclared dynamic
//! build-script reads are outside this contract, never certified by this walk.
use std::{
    collections::BTreeSet,
    fs, io,
    path::{Path, PathBuf},
};
use toml::Value;
pub struct SourceInputs {
    pub files: Vec<PathBuf>,
    pub directories: Vec<PathBuf>,
    pub missing_paths: Vec<PathBuf>,
}
struct Walker {
    root: PathBuf,
    files: BTreeSet<PathBuf>,
    dirs: BTreeSet<PathBuf>,
    seen: BTreeSet<PathBuf>,
    missing: BTreeSet<PathBuf>,
}
fn invalid(s: impl Into<String>) -> io::Error {
    io::Error::other(s.into())
}
fn entries(v: Option<&Value>) -> io::Result<Vec<(&str, &Value)>> {
    match v {
        None => Ok(Vec::new()),
        Some(Value::Table(t)) => Ok(t.iter().map(|(k, v)| (k.as_str(), v)).collect()),
        _ => Err(invalid("expected Cargo table")),
    }
}
impl Walker {
    fn admit(&self, p: &Path) -> io::Result<PathBuf> {
        let p = fs::canonicalize(p)?;
        if !p.starts_with(&self.root) {
            return Err(invalid(format!(
                "Cargo input outside repository: {}",
                p.display()
            )));
        }
        for at in p.ancestors().take_while(|at| *at != self.root) {
            let Some(name) = at.file_name().and_then(|n| n.to_str()) else {
                continue;
            };
            if name == ".git"
                || matches!(name, "target" | "node_modules" | ".cache")
                    && at
                        .parent()
                        .is_some_and(|parent| parent.join("Cargo.toml").is_file())
            {
                return Err(invalid(format!(
                    "Cargo input points into build/cache output: {}",
                    p.display()
                )));
            }
        }
        Ok(p)
    }
    fn walk(&mut self, p: &Path) -> io::Result<()> {
        let p = self.admit(p)?;
        let meta = fs::metadata(&p)?;
        if meta.is_file() {
            self.files.insert(p);
            return Ok(());
        }
        if !meta.is_dir() {
            return Err(invalid("unsupported Cargo source input"));
        }
        let package_root = p.join("Cargo.toml").is_file();
        // Cargo's directory watches recurse into outputs; package roots must
        // not watch their own target directory. Source subtrees remain watched.
        if !package_root {
            self.dirs.insert(p.clone());
        }
        let mut entries = fs::read_dir(&p)?.collect::<io::Result<Vec<_>>>()?;
        entries.sort_by_key(|e| e.file_name());
        for e in entries {
            if e.file_name() == ".git"
                || package_root
                    && matches!(
                        e.file_name().to_str(),
                        Some("target" | "node_modules" | ".cache")
                    )
            {
                continue;
            }
            if e.file_type()?.is_symlink() {
                return Err(invalid(format!(
                    "symlink in Cargo source inputs: {}",
                    e.path().display()
                )));
            }
            self.walk(&e.path())?;
        }
        Ok(())
    }
    fn read(&mut self, p: &Path) -> io::Result<Value> {
        let p = self.admit(p)?;
        self.files.insert(p.clone());
        fs::read_to_string(p)?
            .parse::<Value>()
            .map_err(|e| invalid(e.to_string()))
    }
    fn workspace(&mut self, dir: &Path, own: &Value) -> io::Result<Option<(PathBuf, Value)>> {
        if let Some(explicit) = own.get("package").and_then(|x| x.get("workspace")) {
            let dir = self.admit(
                &dir.join(
                    explicit
                        .as_str()
                        .ok_or_else(|| invalid("package.workspace must be a path"))?,
                ),
            )?;
            let cargo = self.read(&dir.join("Cargo.toml"))?;
            if cargo.get("workspace").is_none() {
                return Err(invalid("explicit workspace has no workspace table"));
            }
            return Ok(Some((dir, cargo)));
        }
        let mut at = Some(dir);
        while let Some(d) = at {
            let p = d.join("Cargo.toml");
            if p.exists() {
                let cargo = self.read(&p)?;
                if cargo.get("workspace").is_some() {
                    return Ok(Some((d.to_path_buf(), cargo)));
                }
            }
            if d == self.root {
                break;
            }
            at = d.parent();
        }
        Ok(None)
    }
    fn source_metadata(&mut self, base: &Path, owner: &Value) -> io::Result<()> {
        for key in ["package", "workspace"] {
            if let Some(inputs) = owner
                .get(key)
                .and_then(|v| v.get("metadata"))
                .and_then(|v| v.get("dq-source-key"))
                .and_then(|v| v.get("inputs"))
            {
                for item in inputs
                    .as_array()
                    .ok_or_else(|| invalid("dq-source-key.inputs must be paths"))?
                {
                    self.walk(
                        &base.join(
                            item.as_str()
                                .ok_or_else(|| invalid("dq-source-key input must be a path"))?,
                        ),
                    )?;
                }
            }
        }
        Ok(())
    }
    fn dependency(
        &mut self,
        name: &str,
        value: &Value,
        base: &Path,
        ws: Option<&(PathBuf, Value)>,
    ) -> io::Result<()> {
        if value.is_str() {
            return Ok(());
        }
        if !value.is_table() {
            return Err(invalid("expected Cargo dependency table"));
        }
        let mut spec = value;
        let mut base = base;
        if spec.get("workspace").and_then(Value::as_bool) == Some(true) {
            let (dir, cargo) =
                ws.ok_or_else(|| invalid(format!("inherited dependency {name} has no workspace")))?;
            spec = cargo
                .get("workspace")
                .and_then(|v| v.get("dependencies"))
                .and_then(|v| v.get(name))
                .ok_or_else(|| invalid(format!("missing workspace dependency {name}")))?;
            if spec.is_str() {
                return Ok(());
            }
            base = dir;
        }
        if let Some(path) = spec.get("path") {
            self.visit(
                &base
                    .join(
                        path.as_str()
                            .ok_or_else(|| invalid("dependency path must be a string"))?,
                    )
                    .join("Cargo.toml"),
            )?;
        }
        Ok(())
    }
    fn dependencies(
        &mut self,
        owner: &Value,
        base: &Path,
        ws: Option<&(PathBuf, Value)>,
    ) -> io::Result<()> {
        for key in ["dependencies", "dev-dependencies", "build-dependencies"] {
            for (name, value) in entries(owner.get(key))? {
                self.dependency(name, value, base, ws)?
            }
        }
        for (_, target) in entries(owner.get("target"))? {
            self.dependencies(target, base, ws)?
        }
        for (_, patch) in entries(owner.get("patch"))? {
            for (name, value) in entries(Some(patch))? {
                self.dependency(name, value, base, ws)?
            }
        }
        for (name, value) in entries(owner.get("replace"))? {
            self.dependency(name, value, base, ws)?
        }
        Ok(())
    }
    fn visit(&mut self, p: &Path) -> io::Result<()> {
        let p = self.admit(p)?;
        if !self.seen.insert(p.clone()) {
            return Ok(());
        }
        let cargo = self.read(&p)?;
        let dir = p
            .parent()
            .ok_or_else(|| invalid("manifest has no parent"))?;
        let ws = self.workspace(dir, &cargo)?;
        self.walk(dir)?;
        let mut bases = vec![dir.to_path_buf()];
        if let Some((w, _)) = &ws {
            if w != dir {
                bases.push(w.clone())
            }
        }
        for base in bases {
            let lock = base.join("Cargo.lock");
            if lock.exists() {
                self.files.insert(self.admit(&lock)?);
            } else {
                self.missing.insert(lock);
            }
        }
        let mut at = Some(dir);
        while let Some(base) = at {
            let config = base.join(".cargo");
            if config.exists() {
                self.walk(&config)?;
            }
            for name in ["config", "config.toml"] {
                let file = config.join(name);
                if !file.exists() {
                    self.missing.insert(file);
                    continue;
                }
                let settings = self.read(&file)?;
                for (_, patch) in entries(settings.get("patch"))? {
                    for (name, value) in entries(Some(patch))? {
                        self.dependency(name, value, base, ws.as_ref())?
                    }
                }
                for (name, value) in entries(settings.get("replace"))? {
                    self.dependency(name, value, base, ws.as_ref())?
                }
                if let Some(paths) = settings.get("paths") {
                    for path in paths
                        .as_array()
                        .ok_or_else(|| invalid("Cargo config paths must be strings"))?
                    {
                        self.visit(
                            &base
                                .join(
                                    path.as_str().ok_or_else(|| {
                                        invalid("Cargo config path must be a string")
                                    })?,
                                )
                                .join("Cargo.toml"),
                        )?;
                    }
                }
            }
            if base == self.root {
                break;
            }
            at = base.parent();
        }
        self.source_metadata(dir, &cargo)?;
        if let Some((base, owner)) = &ws {
            if base != dir {
                self.source_metadata(base, owner)?
            }
        }
        self.dependencies(&cargo, dir, ws.as_ref())?;
        if let Some((base, owner)) = &ws {
            if base != dir {
                // Only workspace patches and replacements are inherited globally.
                for (_, patch) in entries(owner.get("patch"))? {
                    for (name, value) in entries(Some(patch))? {
                        self.dependency(name, value, base, ws.as_ref())?
                    }
                }
                for (name, value) in entries(owner.get("replace"))? {
                    self.dependency(name, value, base, ws.as_ref())?
                }
            }
        }
        Ok(())
    }
}
pub fn source_inputs(root: &Path, manifest: &Path) -> io::Result<SourceInputs> {
    let mut w = Walker {
        root: fs::canonicalize(root)?,
        files: BTreeSet::new(),
        dirs: BTreeSet::new(),
        seen: BTreeSet::new(),
        missing: BTreeSet::new(),
    };
    w.visit(manifest)?;
    Ok(SourceInputs {
        files: w.files.into_iter().collect(),
        directories: w.dirs.into_iter().collect(),
        missing_paths: w.missing.into_iter().collect(),
    })
}
pub fn relative_path(root: &Path, file: &Path) -> io::Result<String> {
    Ok(file
        .strip_prefix(fs::canonicalize(root)?)
        .map_err(|_| invalid("source path outside repository"))?
        .to_string_lossy()
        .replace('\\', "/"))
}
