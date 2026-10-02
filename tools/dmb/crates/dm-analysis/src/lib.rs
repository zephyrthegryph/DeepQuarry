//! Versioned compiler facts. Missing reference coverage is explicit, never guessed.
use dm_ir::Span;
use dm_preprocess::PreprocessedProject;
use dm_semantics::{DeclarationIndex, ProcKind};
use dm_syntax::{AstFile, Item, ItemKind, SegmentedSource};
use serde::{Deserialize, Serialize};
use std::{
    collections::BTreeMap,
    io::{self, BufRead, Write},
};

pub const SCHEMA_VERSION: u32 = 2;
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
    Fragment {
        id: String,
        expanded_start: usize,
        expanded_end: usize,
    },
    ProcedureFragment {
        symbol: String,
        occurrence: u32,
        fragment_id: String,
        body_digest: String,
        location: Option<Location>,
    },
    ResolvedOwner { owner: String, parent: Option<String> },
    ResolvedField { owner: String, name: String, constant: bool, override_only: bool, expression: Option<String> },
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

#[derive(Clone)]
pub struct FrontendFragment {
    /// Content identity excludes absolute offsets and worktree lineage.
    pub id: String,
    pub source_offset: usize,
    pub source_len: usize,
    pub ast: std::sync::Arc<AstFile>,
    pub procedures: std::sync::Arc<[ProcedureFragment]>,
}
#[derive(Clone, Debug)]
pub struct ProcedureFragment {
    pub symbol: String,
    pub local_span: dm_syntax::Span,
    pub body_digest: String,
}
#[derive(Clone, Copy)]
pub struct ItemRef<'a> { pub item: &'a Item, pub source_offset: usize }
impl ItemRef<'_> {
    pub fn span(&self) -> dm_syntax::Span { dm_syntax::Span::new(self.source_offset+self.item.span.start,self.source_offset+self.item.span.end) }
    pub fn header_span(&self) -> dm_syntax::Span { dm_syntax::Span::new(self.source_offset+self.item.header_span.start,self.source_offset+self.item.header_span.end) }
    pub fn children(&self) -> impl Iterator<Item=ItemRef<'_>> { self.item.children.iter().map(move |item|ItemRef { item,source_offset:self.source_offset }) }
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ResolvedOwner { pub owner: String, pub parent: Option<String> }
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ResolvedField { pub owner: String, pub name: String, pub constant: bool, pub override_only: bool, pub expression: Option<String> }
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ResolvedValue {
    pub value: Option<serde_json::Value>,
    /// Exact positive and negative semantic reads from the compiler resolver.
    pub witnesses: Vec<(String,String)>,
}
/// Read-only access to the native compiler's allocation-independent model.
/// Implementations reuse its dependency recording and value caches.
pub trait ResolvedModel: Send+Sync {
    fn owners(&self) -> Vec<ResolvedOwner>;
    fn fields(&self,owner:&str) -> Vec<ResolvedField>;
    fn resolve_value(&self,owner:&str,name:&str) -> ResolvedValue;
}
#[derive(Clone)]
pub struct FrontendView {
    pub fragments: std::sync::Arc<[FrontendFragment]>,
    pub declarations: std::sync::Arc<DeclarationIndex>,
    pub resolved: Option<std::sync::Arc<dyn ResolvedModel>>,
}
impl FrontendView {
    pub fn items(&self) -> impl Iterator<Item=ItemRef<'_>> {
        self.fragments.iter().flat_map(|fragment|fragment.ast.items.iter().map(move |item|ItemRef {item,source_offset:fragment.source_offset}))
    }
    /// Resolve inheritance through the compiler's canonical declaration index.
    pub fn resolve_field(&self,owner:&str,name:&str) -> Option<&dm_semantics::VarDef> {
        let path=dm_ir::TypePath::parse(owner).ok()?;
        let owner=self.declarations.type_id(&path)?;
        self.declarations.resolve_var(owner,name).and_then(|id|self.declarations.vars.get(id.index()))
    }
    pub fn resolve_procedure(&self,owner:&str,name:&str,kind:ProcKind) -> Option<&dm_semantics::ProcDef> {
        let path=dm_ir::TypePath::parse(owner).ok()?;
        let owner=self.declarations.type_id(&path)?;
        self.declarations.resolve_proc(owner,name,kind).and_then(|id|self.declarations.procs.get(id.index()))
    }
    pub fn fragment_at(&self,offset:usize) -> Option<&FrontendFragment> {
        let index=self.fragments.partition_point(|fragment|fragment.source_offset<=offset).checked_sub(1)?;
        let fragment=&self.fragments[index];
        (offset<fragment.source_offset+fragment.source_len).then_some(fragment)
    }
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
struct Locations<'a> {
    project: &'a PreprocessedProject,
    line_starts: Vec<usize>,
    origins: Vec<usize>,
    source: Option<&'a SegmentedSource>,
}
impl<'a> Locations<'a> {
    fn new(project: &'a PreprocessedProject) -> Self {
        let mut line_starts = vec![0];
        line_starts.extend(
            project
                .text
                .bytes()
                .enumerate()
                .filter_map(|(i, b)| (b == b'\n').then_some(i + 1)),
        );
        let mut origins: Vec<_> = (0..project.origins.len()).collect();
        origins.sort_by_key(|&i| project.origins[i].output_line);
        Self {
            project,
            line_starts,
            origins,
            source: None,
        }
    }
    fn segmented(project: &'a PreprocessedProject, source: &'a SegmentedSource) -> Self {
        let mut origins: Vec<_> = (0..project.origins.len()).collect();
        origins.sort_by_key(|&i| project.origins[i].output_line);
        Self { project, line_starts: vec![], origins, source: Some(source) }
    }
    fn get(&self, span: Span) -> Option<Location> {
        if span.file.0 != 0
            || span.start > span.end
            || span.end as usize > self.source.map_or(self.project.text.len(), SegmentedSource::len)
            || !self.source.map_or_else(|| self.project.text.is_char_boundary(span.start as usize), |source| source.is_char_boundary(span.start as usize))
        {
            return None;
        }
        let line = self.source.and_then(|source| source.line_number(span.start as usize))
            .unwrap_or_else(|| self.line_starts.partition_point(|&start| start <= span.start as usize));
        let origin = if self.project.origin_map.is_some() {
            self.project.origin_at_line(line)?
        } else {
            let pos=self.origins.partition_point(|&i|self.project.origins[i].output_line<=line);
            let origin=&self.project.origins[*self.origins.get(pos.checked_sub(1)?)?];
            if origin.output_line!=line {return None;}
            origin.clone()
        };
        Some(Location {
            file: origin.path.to_string_lossy().into_owned(),
            line: origin.source_line,
            expanded_start: span.start,
            expanded_end: span.end,
        })
    }
}
/// Maximum encoded size of one JSONL fact, including its newline.
pub const MAX_JSONL_RECORD_BYTES: usize = 8 * 1024 * 1024;
fn read_record(input: &mut impl BufRead) -> io::Result<Option<String>> {
    let mut bytes = Vec::new();
    loop {
        let buffer = input.fill_buf()?;
        if buffer.is_empty() {
            return if bytes.is_empty() {
                Ok(None)
            } else {
                String::from_utf8(bytes).map(Some).map_err(io::Error::other)
            };
        }
        let count = buffer
            .iter()
            .position(|&b| b == b'\n')
            .map_or(buffer.len(), |i| i + 1);
        if bytes.len().saturating_add(count) > MAX_JSONL_RECORD_BYTES {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "analysis record exceeds byte limit",
            ));
        }
        let done = buffer[count - 1] == b'\n';
        bytes.extend_from_slice(&buffer[..count]);
        input.consume(count);
        if done {
            return String::from_utf8(bytes).map(Some).map_err(io::Error::other);
        }
    }
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
        Self::from_frontend_source(input_digest, index, ast, project, None)
    }
    /// Analyze the same shared expansion pieces consumed by native compilation.
    pub fn from_frontend_segmented(
        input_digest: impl Into<String>, index: &DeclarationIndex, ast: &AstFile,
        project: &PreprocessedProject, source: &SegmentedSource,
    ) -> Self {
        Self::from_frontend_source(input_digest, index, ast, project, Some(source))
    }
    fn from_frontend_source(
        input_digest: impl Into<String>, index: &DeclarationIndex, ast: &AstFile,
        project: &PreprocessedProject, source: Option<&SegmentedSource>,
    ) -> Self {
        Self::from_fragment_sources(input_digest,index,&[(0,ast)],project,source)
    }
    pub fn from_shared_frontend(input_digest: impl Into<String>,view:&FrontendView,project:&PreprocessedProject,source:&SegmentedSource) -> Self {
        let fragments: Vec<_>=view.fragments.iter().map(|fragment|(fragment.source_offset,fragment.ast.as_ref())).collect();
        let mut snapshot=Self::from_fragment_sources(input_digest,&view.declarations,&fragments,project,Some(source));
        let locations=Locations::segmented(project,source);
        let mut occurrences=BTreeMap::<&str,u32>::new();
        for fragment in view.fragments.iter() {
            snapshot.facts.push(Fact::Fragment {id:fragment.id.clone(),expanded_start:fragment.source_offset,expanded_end:fragment.source_offset+fragment.source_len});
            for procedure in fragment.procedures.iter() {
                let occurrence=occurrences.entry(&procedure.symbol).or_default();
                snapshot.facts.push(Fact::ProcedureFragment {symbol:procedure.symbol.clone(),occurrence:*occurrence,fragment_id:fragment.id.clone(),body_digest:procedure.body_digest.clone(),location:locations.get(Span {file:dm_ir::FileId(0),start:(fragment.source_offset+procedure.local_span.start) as u32,end:(fragment.source_offset+procedure.local_span.end) as u32})});
                *occurrence+=1;
            }
        }
        if let Some(model)=&view.resolved {
            let mut owners=model.owners();owners.insert(0,ResolvedOwner {owner:String::new(),parent:None});
            for owner in owners {
                snapshot.facts.push(Fact::ResolvedOwner {owner:owner.owner.clone(),parent:owner.parent});
                for field in model.fields(&owner.owner) {
                    snapshot.facts.push(Fact::ResolvedField {owner:field.owner,name:field.name,constant:field.constant,override_only:field.override_only,expression:field.expression});
                }
            }
        }
        snapshot
    }
    fn from_fragment_sources(input_digest:impl Into<String>,index:&DeclarationIndex,fragments:&[(usize,&AstFile)],project:&PreprocessedProject,source:Option<&SegmentedSource>) -> Self {
        let locations = source.map_or_else(|| Locations::new(project), |source| Locations::segmented(project, source));
        let mut line_number = 0;
        let mut line_present = |text: &str| {
            line_number += 1;
            if text.trim().is_empty() { return true; }
            project.origin_at_line(line_number).is_some()
        };
        let complete = if let Some(source) = source {
            // Expansion pieces end at newlines; retain a carry for general callers.
            let mut carry = String::new();
            let mut complete = true;
            let scanned=source.visit_pieces(|piece| {
                for part in piece.split_inclusive('\n') {
                    carry.push_str(part);
                    if part.ends_with('\n') {
                        complete &= line_present(&carry);
                        carry.clear();
                    }
                }
            });
            if !carry.is_empty() { complete &= line_present(&carry); }
            complete && scanned.is_ok()
        } else { project.text.lines().all(&mut line_present) };
        let origin_coverage = if project.origin_count() == 0 { Coverage::Unavailable }
            else if complete { Coverage::Complete } else { Coverage::Partial };
        let mut result = Self {
            input_digest: input_digest.into(),
            coverage: CoverageReport {
                declarations: if fragments.iter().any(|(_,ast)|incomplete(&ast.items) || !ast.diagnostics.is_empty()) {
                    Coverage::Partial
                } else {
                    Coverage::Complete
                },
                inheritance: Coverage::Complete,
                signatures: Coverage::Partial,
                origins: origin_coverage,
                references: Coverage::Unavailable,
                diagnostics: Coverage::Partial,
            },
            facts: vec![],
        };
        let mut proc_headers = BTreeMap::new();
        for (offset,ast) in fragments {
            let mut local=BTreeMap::new();headers(&ast.items,&mut local);
            proc_headers.extend(local.into_iter().map(|(start,header)|(start+offset,header)));
        }
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
                    location: locations.get(*span),
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
                location: locations.get(var.span),
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
                location: locations.get(proc_.span),
                synthetic: false,
            });
            if let Some(header) = proc_headers.get(&(proc_.span.start as usize)) {
                result.facts.push(Fact::Signature {
                    symbol,
                    occurrence: proc_.occurrence,
                    header: header.clone(),
                    location: locations.get(proc_.span),
                });
            }
        }
        for origin in project.origin_iter() {
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
        for (offset,ast) in fragments { for d in &ast.diagnostics {
            result.facts.push(Fact::Diagnostic {
                severity: "error".into(),
                category: format!("syntax::{:?}", d.kind),
                message: d.message.clone(),
                location: locations.get(Span {
                    file: dm_ir::FileId(0),
                    start: (offset+d.span.start) as u32,
                    end: (offset+d.span.end) as u32,
                }),
            });
        }
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
    pub fn read_jsonl(mut input: impl BufRead) -> io::Result<Self> {
        let header =
            read_record(&mut input)?.ok_or_else(|| io::Error::other("missing analysis header"))?;
        let Fact::Snapshot {
            schema,
            input_digest,
            coverage,
        } = serde_json::from_str(&header).map_err(io::Error::other)?
        else {
            return Err(io::Error::other("first record must be snapshot"));
        };
        if schema != SCHEMA_VERSION && schema != 1 {
            return Err(io::Error::other("unsupported analysis schema"));
        }
        let mut facts = vec![];
        while let Some(line) = read_record(&mut input)? {
            let fact = serde_json::from_str(&line).map_err(io::Error::other)?;
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
    fn indexed_locations_follow_multiple_origins_and_reader_is_bounded() {
        let project = PreprocessedProject {
            text: "one\ntwo\nthree\nfour\n".into(),
            origins: vec![
                dm_preprocess::Origin {
                    output_line: 1,
                    path: std::sync::Arc::new("a.dm".into()),
                    source_line: 10,
                },
                dm_preprocess::Origin {
                    output_line: 3,
                    path: std::sync::Arc::new("b.dm".into()),
                    source_line: 20,
                },
            ],
            ..Default::default()
        };
        let locations = Locations::new(&project);
        for (start, file, line) in [(0, "a.dm", 10), (8, "b.dm", 20)] {
            let actual = locations
                .get(Span {
                    file: dm_ir::FileId(0),
                    start,
                    end: start + 1,
                })
                .unwrap();
            assert_eq!((actual.file.as_str(), actual.line), (file, line));
        }
        for start in [4, 14] {
            assert!(locations
                .get(Span {
                    file: dm_ir::FileId(0),
                    start,
                    end: start + 1,
                })
                .is_none());
        }
        let ast = dm_syntax::parse(&project.text);
        let index = DeclarationIndex::build(vec![]).unwrap();
        let snapshot = Snapshot::from_frontend("sparse", &index, &ast, &project);
        assert_eq!(snapshot.coverage.origins, Coverage::Partial);
        let too_large = vec![b'x'; MAX_JSONL_RECORD_BYTES + 1];
        assert!(read_record(&mut std::io::Cursor::new(too_large)).is_err());
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
