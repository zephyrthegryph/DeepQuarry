//! Versioned compiler facts. Missing reference coverage is explicit, never guessed.
use dm_ir::Span;
use dm_preprocess::PreprocessedProject;
use dm_semantics::{DeclarationIndex, ProcKind};
use dm_syntax::{AstFile, Item, ItemKind};
use serde::{Deserialize, Serialize};
use std::{
    collections::BTreeMap,
    io::{self, BufRead, Write},
};

pub const SCHEMA_VERSION: u32 = 1;
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct Location {
    pub file: String,
    pub line: usize,
    pub expanded_start: u32,
    pub expanded_end: u32,
}
#[derive(Clone, Copy, Debug, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Coverage {
    #[default]
    Unavailable,
    Partial,
    Complete,
}
#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq, Eq)]
pub struct CoverageReport {
    pub declarations: Coverage,
    pub signatures: Coverage,
    pub inheritance: Coverage,
    pub origins: Coverage,
    pub references: Coverage,
    pub diagnostics: Coverage,
}
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "record", rename_all = "snake_case")]
pub enum Fact {
    Snapshot {
        schema: u32,
        input_digest: String,
        coverage: CoverageReport,
    },
    Declaration {
        symbol: String,
        kind: String,
        occurrence: u32,
        location: Option<Location>,
        synthetic: bool,
    },
    /// Exact authored header; parameter types/defaults are not claimed resolved.
    Signature {
        symbol: String,
        occurrence: u32,
        header: String,
        location: Option<Location>,
    },
    Inheritance {
        child: String,
        parent: String,
        explicit: bool,
    },
    Origin {
        expanded_line: usize,
        file: String,
        source_line: usize,
    },
    /// Target is a canonical compiler symbol only when the producer resolved it.
    Reference {
        from: String,
        spelling: String,
        target: Option<String>,
        dynamic: bool,
        location: Option<Location>,
    },
    Diagnostic {
        severity: String,
        category: String,
        message: String,
        location: Option<Location>,
    },
}
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct Snapshot {
    pub input_digest: String,
    pub coverage: CoverageReport,
    pub facts: Vec<Fact>,
}

fn proc_path(owner: &str, name: &str, kind: ProcKind) -> String {
    format!(
        "{}/{}/{}",
        owner.trim_end_matches('/'),
        if kind == ProcKind::Verb {
            "verb"
        } else {
            "proc"
        },
        name
    )
}
fn location(span: Span, project: &PreprocessedProject) -> Option<Location> {
    // The existing declaration index uses expanded-file ID zero. Other IDs must
    // be mapped by a future producer rather than falsely attributed to this text.
    if span.file.0 != 0 || span.start > span.end || span.end as usize > project.text.len() {
        return None;
    }
    let prefix = project.text.get(..span.start as usize)?;
    let line = prefix.bytes().filter(|b| *b == b'\n').count() + 1;
    let origin = project
        .origins
        .iter()
        .rev()
        .find(|o| o.output_line <= line)?;
    Some(Location {
        file: origin.path.to_string_lossy().into_owned(),
        line: origin.source_line + line - origin.output_line,
        expanded_start: span.start,
        expanded_end: span.end,
    })
}
fn headers(items: &[Item], out: &mut BTreeMap<usize, String>) {
    for item in items {
        if matches!(item.kind, ItemKind::Proc | ItemKind::Verb) {
            out.insert(item.span.start, item.header.clone());
        }
        headers(&item.children, out);
    }
}
fn incomplete(items: &[Item]) -> bool {
    items
        .iter()
        .any(|item| item.kind == ItemKind::Unknown || incomplete(&item.children))
}
impl Snapshot {
    /// Export actual declaration-index facts and exact parser headers. References
    /// remain unavailable until supplied by the semantic resolution producer.
    pub fn from_frontend(
        input_digest: impl Into<String>,
        index: &DeclarationIndex,
        ast: &AstFile,
        project: &PreprocessedProject,
    ) -> Self {
        let mut result = Self {
            input_digest: input_digest.into(),
            coverage: CoverageReport {
                declarations: if incomplete(&ast.items) || !ast.diagnostics.is_empty() {
                    Coverage::Partial
                } else {
                    Coverage::Complete
                },
                inheritance: Coverage::Complete,
                signatures: Coverage::Partial,
                origins: if project.origins.is_empty() {
                    Coverage::Unavailable
                } else {
                    Coverage::Complete
                },
                references: Coverage::Unavailable,
                diagnostics: Coverage::Partial,
            },
            facts: vec![],
        };
        let mut proc_headers = BTreeMap::new();
        headers(&ast.items, &mut proc_headers);
        for ty in &index.types {
            if ty.declarations.is_empty() {
                result.facts.push(Fact::Declaration {
                    symbol: ty.path.to_string(),
                    kind: "type".into(),
                    occurrence: 0,
                    location: None,
                    synthetic: ty.synthetic,
                });
            }
            for (occurrence, span) in ty.declarations.iter().enumerate() {
                result.facts.push(Fact::Declaration {
                    symbol: ty.path.to_string(),
                    kind: "type".into(),
                    occurrence: occurrence as u32,
                    location: location(*span, project),
                    synthetic: ty.synthetic,
                });
            }
            if let Some(parent) = ty.parent {
                result.facts.push(Fact::Inheritance {
                    child: ty.path.to_string(),
                    parent: index.types[parent.index()].path.to_string(),
                    explicit: ty.explicit_parent.is_some(),
                });
            }
        }
        for var in &index.vars {
            result.facts.push(Fact::Declaration {
                symbol: format!(
                    "{}/var/{}",
                    index.types[var.owner.index()]
                        .path
                        .as_str()
                        .trim_end_matches('/'),
                    var.name
                ),
                kind: if var.is_static { "static_var" } else { "var" }.into(),
                occurrence: var.occurrence,
                location: location(var.span, project),
                synthetic: false,
            });
        }
        for proc_ in &index.procs {
            let symbol = proc_path(
                index.types[proc_.owner.index()].path.as_str(),
                &proc_.name,
                proc_.kind,
            );
            result.facts.push(Fact::Declaration {
                symbol: symbol.clone(),
                kind: if proc_.kind == ProcKind::Verb {
                    "verb"
                } else {
                    "proc"
                }
                .into(),
                occurrence: proc_.occurrence,
                location: location(proc_.span, project),
                synthetic: false,
            });
            if let Some(header) = proc_headers.get(&(proc_.span.start as usize)) {
                result.facts.push(Fact::Signature {
                    symbol,
                    occurrence: proc_.occurrence,
                    header: header.clone(),
                    location: location(proc_.span, project),
                });
            }
        }
        for origin in &project.origins {
            result.facts.push(Fact::Origin {
                expanded_line: origin.output_line,
                file: origin.path.to_string_lossy().into_owned(),
                source_line: origin.source_line,
            });
        }
        for d in &project.diagnostics {
            result.facts.push(Fact::Diagnostic {
                severity: "error".into(),
                category: format!("preprocess::{:?}", d.kind),
                message: d.message.clone(),
                location: Some(Location {
                    file: d.path.to_string_lossy().into_owned(),
                    line: d.line,
                    expanded_start: 0,
                    expanded_end: 0,
                }),
            });
        }
        for d in &ast.diagnostics {
            result.facts.push(Fact::Diagnostic {
                severity: "error".into(),
                category: format!("syntax::{:?}", d.kind),
                message: d.message.clone(),
                location: location(
                    Span {
                        file: dm_ir::FileId(0),
                        start: d.span.start as u32,
                        end: d.span.end as u32,
                    },
                    project,
                ),
            });
        }
        result
    }
    /// The caller must set honest coverage for the supplied semantic reference batch.
    pub fn add_references(
        &mut self,
        references: impl IntoIterator<Item = Fact>,
        coverage: Coverage,
    ) -> io::Result<()> {
        let facts = references.into_iter().collect::<Vec<_>>();
        if facts
            .iter()
            .any(|fact| !matches!(fact, Fact::Reference { .. }))
        {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "reference producer supplied another fact kind",
            ));
        }
        self.facts.extend(facts);
        self.coverage.references = coverage;
        Ok(())
    }
    pub fn write_jsonl(&self, mut output: impl Write) -> io::Result<()> {
        let header = Fact::Snapshot {
            schema: SCHEMA_VERSION,
            input_digest: self.input_digest.clone(),
            coverage: self.coverage.clone(),
        };
        for fact in std::iter::once(&header).chain(self.facts.iter()) {
            serde_json::to_writer(&mut output, fact).map_err(io::Error::other)?;
            output.write_all(b"\n")?;
        }
        Ok(())
    }
    pub fn read_jsonl(input: impl BufRead) -> io::Result<Self> {
        let mut lines = input.lines();
        let header = lines
            .next()
            .ok_or_else(|| io::Error::other("missing analysis header"))??;
        let Fact::Snapshot {
            schema,
            input_digest,
            coverage,
        } = serde_json::from_str(&header).map_err(io::Error::other)?
        else {
            return Err(io::Error::other("first record must be snapshot"));
        };
        if schema != SCHEMA_VERSION {
            return Err(io::Error::other("unsupported analysis schema"));
        }
        let mut facts = vec![];
        for line in lines {
            let fact = serde_json::from_str(&line?).map_err(io::Error::other)?;
            if matches!(fact, Fact::Snapshot { .. }) {
                return Err(io::Error::other("duplicate snapshot header"));
            }
            facts.push(fact);
        }
        Ok(Self {
            input_digest,
            coverage,
            facts,
        })
    }
    pub fn persist(
        &self,
        store: &dm_store::Store,
        key: dm_store::Key,
        witnesses: &[dm_store::ReadWitness],
    ) -> io::Result<dm_store::Commit> {
        let mut bytes = vec![];
        self.write_jsonl(&mut bytes)?;
        store.commit(witnesses, &[dm_store::Change::Put(key, bytes)], None)
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn jsonl_roundtrip_preserves_negative_reference_and_partial_coverage() {
        let mut snapshot = Snapshot {
            input_digest: "source-sha".into(),
            coverage: CoverageReport::default(),
            facts: vec![Fact::Signature {
                symbol: "/proc/example".into(),
                occurrence: 0,
                header: "/proc/example(value = list(1, 2))".into(),
                location: None,
            }],
        };
        snapshot
            .add_references(
                [Fact::Reference {
                    from: "/proc/example".into(),
                    spelling: "missing".into(),
                    target: None,
                    dynamic: false,
                    location: None,
                }],
                Coverage::Partial,
            )
            .unwrap();
        let mut bytes = vec![];
        snapshot.write_jsonl(&mut bytes).unwrap();
        assert_eq!(
            Snapshot::read_jsonl(std::io::Cursor::new(bytes)).unwrap(),
            snapshot
        );
        assert_eq!(snapshot.coverage.references, Coverage::Partial);
        assert!(Snapshot::read_jsonl(std::io::Cursor::new(b"{\"record\":\"snapshot\",\"schema\":99,\"input_digest\":\"x\",\"coverage\":{\"declarations\":\"unavailable\",\"signatures\":\"unavailable\",\"inheritance\":\"unavailable\",\"origins\":\"unavailable\",\"references\":\"unavailable\",\"diagnostics\":\"unavailable\"}}\n")).is_err());
    }
    #[test]
    fn frontend_export_keeps_explicit_inheritance_and_source_origin() {
        use dm_ir::{FileId, TypePath};
        use dm_semantics::{Declaration, DeclarationKind};
        let project = PreprocessedProject {
            text: "/datum/child\n".into(),
            origins: vec![dm_preprocess::Origin {
                output_line: 1,
                path: std::sync::Arc::new("included.dm".into()),
                source_line: 7,
            }],
            ..Default::default()
        };
        let index = DeclarationIndex::build([
            Declaration {
                kind: DeclarationKind::Type {
                    path: TypePath::parse("/datum/base").unwrap(),
                    explicit_parent: None,
                },
                span: Span {
                    file: FileId(0),
                    start: 0,
                    end: 12,
                },
            },
            Declaration {
                kind: DeclarationKind::Type {
                    path: TypePath::parse("/datum/child").unwrap(),
                    explicit_parent: Some(TypePath::parse("/datum/base").unwrap()),
                },
                span: Span {
                    file: FileId(0),
                    start: 0,
                    end: 12,
                },
            },
        ])
        .unwrap();
        let snapshot = Snapshot::from_frontend("x", &index, &AstFile::default(), &project);
        assert!(snapshot.facts.iter().any(|f|matches!(f,Fact::Inheritance{child,parent,explicit:true} if child=="/datum/child" && parent=="/datum/base")));
        assert!(snapshot.facts.iter().any(|f|matches!(f,Fact::Declaration{location:Some(Location{line:7,file,..}),..} if file=="included.dm")));
        assert_eq!(snapshot.coverage.references, Coverage::Unavailable);
    }
}
