//! Compact source-definition facts shared by declaration-only Analyze policies.
//!
//! Matches Sem's definition index: own variable declarations and all authored
//! proc/verb occurrences, no bare type headers and no inherited copies. This
//! borrows the issued compiler archive and never parses executable syntax.
use crate::untyped::Unsupported;
use dm_ir::SymbolId;
use dm_tree::{
    frontend::{BodyArchive, SourceLocation},
    DefinitionMode, MemberId, MemberKind,
};
use std::{collections::BTreeMap, path::Path};

#[derive(Clone, Copy, Debug)]
enum Anchor {
    Variable(MemberId),
    Callable(usize),
}

/// The archive binding is private: a source identity cannot be rebound merely
/// because another frontend happens to issue equal dense member IDs.
#[derive(Clone, Copy)]
pub struct SourceDefinition<'a> {
    archive: &'a BodyArchive,
    member: MemberId,
    owner: SymbolId,
    name: SymbolId,
    kind: MemberKind,
    line: usize,
    anchor: Anchor,
    ordinal: u32,
}
impl<'a> SourceDefinition<'a> {
    pub fn member(&self) -> MemberId {
        self.member
    }
    pub fn owner(&self) -> SymbolId {
        self.owner
    }
    pub fn name(&self) -> SymbolId {
        self.name
    }
    pub fn kind(&self) -> MemberKind {
        self.kind
    }
    pub fn line(&self) -> usize {
        self.line
    }
    /// The compiler's normalized owner-local callable ordinal. Variables have
    /// no procedure ordinal. This is not the declaration or body-roster index.
    pub fn procedure_ordinal(&self) -> Option<u32> {
        (self.kind != MemberKind::Var).then_some(self.ordinal)
    }
    pub fn owner_text(&self) -> &'a str {
        self.archive
            .tree()
            .symbols()
            .text(self.owner)
            .expect("validated source definition owner")
    }
    pub fn name_text(&self) -> &'a str {
        self.archive
            .tree()
            .symbols()
            .text(self.name)
            .expect("validated source definition name")
    }
    pub fn origin(&self) -> Result<SourceLocation, Unsupported> {
        match self.anchor {
            Anchor::Variable(member) => self.archive.member_location(member),
            Anchor::Callable(ordinal) => self
                .archive
                .occurrences()
                .get(ordinal)
                .map(|body| body.source.clone()),
        }
        .ok_or_else(|| Unsupported("source definition's issued origin is unavailable".into()))
    }
}

pub struct SourceDefinitionIndex<'a> {
    archive: &'a BodyArchive,
    files: BTreeMap<String, Vec<SourceDefinition<'a>>>,
}
impl<'a> SourceDefinitionIndex<'a> {
    /// Captures compact per-file contributions only; the tree/source/syntax
    /// owners remain in the compiler archive, without another program model.
    pub fn capture(archive: &'a BodyArchive, root: &Path) -> Result<Self, Unsupported> {
        let tree = archive.tree();
        let mut files: BTreeMap<String, Vec<SourceDefinition<'a>>> = BTreeMap::new();
        for (index, member) in tree.members().iter().enumerate() {
            if member.kind != MemberKind::Var || member.definition != DefinitionMode::Declare {
                continue;
            }
            let id = MemberId(
                index
                    .try_into()
                    .map_err(|_| Unsupported("source definition index overflow".into()))?,
            );
            let source = archive
                .member_location(id)
                .ok_or_else(|| Unsupported("variable definition has no issued origin".into()))?;
            append(&mut files, archive, root, id, Anchor::Variable(id), &source)?;
        }
        for (ordinal, body) in archive.occurrences().iter().enumerate() {
            let member = tree
                .member(body.member)
                .ok_or_else(|| Unsupported("callable definition member is absent".into()))?;
            if !matches!(member.kind, MemberKind::Proc | MemberKind::Verb)
                || member.metadata.procedure.is_none()
            {
                return Err(Unsupported(
                    "callable definition metadata is incomplete".into(),
                ));
            }
            append(
                &mut files,
                archive,
                root,
                body.member,
                Anchor::Callable(ordinal),
                &body.source,
            )?;
        }
        for rows in files.values_mut() {
            // Sem::build sorts (model line, owner spelling, member spelling),
            // retaining equal rows. Do not use hashed SymbolId ordering here.
            // For equal report tuples legacy builds vars before procs, and a
            // proc's formal body before its same-owner overrides. Those ties
            // can share a physical line after macro/semicolon expansion.
            rows.sort_by(|a, b| {
                (
                    a.line,
                    a.owner_text(),
                    a.name_text(),
                    u8::from(a.kind != MemberKind::Var),
                    a.ordinal,
                )
                    .cmp(&(
                        b.line,
                        b.owner_text(),
                        b.name_text(),
                        u8::from(b.kind != MemberKind::Var),
                        b.ordinal,
                    ))
            });
        }
        Ok(Self { archive, files })
    }
    pub fn archive(&self) -> &'a BodyArchive {
        self.archive
    }
    /// Exact normalized repo-relative key, as the legacy Sem API expects.
    pub fn defs_in(&self, file: &str) -> &[SourceDefinition<'a>] {
        self.files.get(file).map_or(&[], Vec::as_slice)
    }
    pub fn files(&self) -> impl Iterator<Item = (&str, &[SourceDefinition<'a>])> {
        self.files
            .iter()
            .map(|(file, rows)| (file.as_str(), rows.as_slice()))
    }
    /// Nearest definition at/before the line, followed by the next definition
    /// after it if that owner differs. A bare type header creates no candidate.
    pub fn owner_candidates(&self, file: &str, line: usize) -> Vec<SymbolId> {
        let rows = self.defs_in(file);
        let at = rows.partition_point(|row| row.line <= line);
        let mut owners = Vec::new();
        if at > 0 {
            owners.push(rows[at - 1].owner);
        }
        if at < rows.len() && !owners.contains(&rows[at].owner) {
            owners.push(rows[at].owner);
        }
        owners
    }
    pub fn def_at(&self, file: &str, line: usize) -> Option<&SourceDefinition<'a>> {
        let rows = self.defs_in(file);
        rows.partition_point(|row| row.line <= line)
            .checked_sub(1)
            .map(|at| &rows[at])
    }
    pub fn reader_ident(&self, file: &str, line: usize) -> String {
        self.def_at(file, line).map_or_else(
            || "?".into(),
            |row| format!("{}::{}", row.owner_text(), row.name_text()),
        )
    }
}

fn append<'a>(
    files: &mut BTreeMap<String, Vec<SourceDefinition<'a>>>,
    archive: &'a BodyArchive,
    root: &Path,
    id: MemberId,
    anchor: Anchor,
    source: &SourceLocation,
) -> Result<(), Unsupported> {
    let tree = archive.tree();
    let member = tree
        .member(id)
        .ok_or_else(|| Unsupported("source definition member is absent".into()))?;
    let owner = tree
        .type_node(member.owner)
        .ok_or_else(|| Unsupported("source definition owner is absent".into()))?
        .path;
    if tree.symbols().text(owner).is_none() || tree.symbols().text(member.name).is_none() {
        return Err(Unsupported("source definition spelling unavailable".into()));
    }
    if source.line == 0 || source.path.as_os_str().is_empty() {
        return Err(Unsupported("source definition has no issued origin".into()));
    }
    let ordinal = if member.kind == MemberKind::Var {
        0
    } else {
        tree.member_occurrence(id)
            .ok_or_else(|| Unsupported("source callable ordinal unavailable".into()))?
    };
    files
        .entry(file(root, source))
        .or_default()
        .push(SourceDefinition {
            archive,
            member: id,
            owner,
            name: member.name,
            kind: member.kind,
            line: source.line,
            anchor,
            ordinal,
        });
    Ok(())
}
fn file(root: &Path, source: &SourceLocation) -> String {
    // Report-only filesystem equivalence. Keep original provider/origin keys;
    // only the shared safe ordinary-DOS/verbatim comparison may unify paths.
    dm_preprocess::regions::relative_filesystem_path(source.path.as_path(), root)
        .as_deref()
        .unwrap_or(source.path.as_path())
        .to_string_lossy()
        .replace('\\', "/")
}

#[cfg(test)]
#[path = "source_definitions_tests.rs"]
mod tests;
