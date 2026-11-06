//! Shared map edit matchers. Filesystem and semantic authority belong to callers.
use crate::lint::{Meta, Policy, RuleMeta, ScanKind, Site, Sink};
use crate::key_policy_control::{self as kc, Control, Compatibility};
use crate::tree::CODE_DM;
use std::collections::{BTreeMap, BTreeSet};

pub static META: Meta = Meta {
    name: crate::allow_registry_fields::map_edits::SCOPE_META_0.name,
    group: crate::allow_registry_fields::map_edits::SCOPE_META_0.group,
    label: "map_edits",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[
        RuleMeta {
            name: "unknown_var",
            hint: "the map edits a var the type does not have, so the value is lost when the map loads: give the loader a mapping (world/proc/map_edit_moved_var) or fix the map",
        },
        RuleMeta { name: "unknown_type", hint: "the map places a type that no longer exists: restore the path or fix the map" },
    ],
    allow: crate::allow_registry_fields::map_edits::ALLOW_0,
    lists: crate::allow_registry_fields::map_edits::SCOPE_META_0.lists,
};

/// Mapping aids nothing loads.
const SKIP: &[&str] = &["maps/palettes/", "maps/_templates_and_guidance/", "maps/~map_system/"];
/// The vars world/proc/map_edit_moved_var() carries over by name.
const MOVED: &[&str] = &["light_range", "light_power", "light_color", "emagged", "cap_state", "req_access_txt", "req_one_access_txt"];
const SKIP_NAMES: &[&str] = &["1mapping_palette.dmm", "SouthernCrossRef.dmm"];

/// Parse physical edit candidates from the original map text. Keep only borrowed
/// slices while the text is live; the native capture owns the unique result.
fn visit_edits<'a, E>(
    text: &'a str,
    mut poll: impl FnMut() -> Result<(), E>,
    mut visit: impl FnMut(&'a str, &'a str, usize) -> Result<(), E>,
) -> Result<(), E> {
    let mut current = None;
    for (index, line) in text.lines().enumerate() {
        poll()?;
        let number = index + 1;
        let t = line.trim();
        if let Some(open) = t.find('{').filter(|_| current.is_none() && t.starts_with('/')) {
            let ty = &t[..open];
            let rest = &t[open + 1..];
            for piece in rest.trim_end_matches([',', ')']).trim_end_matches('}').split(';') {
                poll()?;
                if let Some((name, _)) = piece.split_once(" = ") {
                    visit(ty, name.trim(), number)?;
                }
            }
            if !t.contains('}') {
                current = Some(ty);
            }
            continue;
        }
        if let Some(ty) = current {
            if let Some((name, _)) = t.split_once(" = ") {
                if name.chars().all(|c| c.is_alphanumeric() || c == '_') {
                    visit(ty, name, number)?;
                }
            }
            if t.contains('}') && !t.contains('"') || t.ends_with('}') || t.ends_with("},") || t.ends_with("})") {
                current = None;
            }
        }
    }
    poll()
}

fn edits(text: &str) -> BTreeMap<(&str, &str), usize> {
    let mut found = BTreeMap::new();
    let parsed = visit_edits(text, || Ok::<(), std::convert::Infallible>(()), |ty, var, line| {
        found.entry((ty, var)).or_insert(line);
        Ok(())
    });
    match parsed { Ok(()) => found, Err(never) => match never {} }
}

/// Data from one complete map. This retains each type spelling once per map,
/// with unique variable spellings and first-line data in legacy sorted order.
/// It has no filesystem authority.
pub struct ParsedMap {
    types: Vec<ParsedType>,
}

struct ParsedType {
    path: String,
    fields: Vec<(String, usize)>,
}

impl ParsedMap {
    #[cfg(feature = "native-policy")]
    pub fn parse(
        bytes: &[u8],
        budget: &std::sync::Arc<crate::captured_generator_budget::Budget>,
        poll: &dyn Fn() -> std::io::Result<()>,
    ) -> Result<Self, crate::captured_reactive_reads::Failure> {
        use crate::{captured_allow_annotations::Operation, key_policy_control::{self as kc, Control}};
        use std::{cell::RefCell, io};

        // Current byte payload is caller-owned. Keep the map decoding and
        // borrowed candidate roster in one refundable scope; only compact
        // unique rows cross it, after charging the retained owner below.
        let oom = |message| io::Error::new(io::ErrorKind::OutOfMemory, message);
        let scratch = crate::captured_generator_budget::Budget::scoped_temporaries(budget).map_err(oom)?;
        let work = RefCell::new(Operation { budget: &scratch, poll });
        work.borrow_mut().checkpoint()?;
        if std::str::from_utf8(bytes).is_err() {
            // The standard lossy conversion appends U+FFFD (up to three
            // bytes per input byte), plus old/new String growth overlap.
            kc::reserve(&mut *work.borrow_mut(), || bytes.len().checked_mul(12)?.checked_add(256))?;
        }
        let text = String::from_utf8_lossy(bytes);
        let mut borrowed = Vec::new();
        visit_edits(&text, || work.borrow_mut().checkpoint(), |ty, var, line| {
            kc::row(&mut *work.borrow_mut(), &mut borrowed)?;
            borrowed.push((ty, var, line));
            Ok(())
        })?;
        // Ties are ordered by physical line, so dedup retains exactly the
        // first observation. Unstable sort needs no separate sort buffer.
        borrowed.sort_unstable();
        work.borrow_mut().checkpoint()?;
        borrowed.dedup_by(|a, b| (a.0, a.1) == (b.0, b.1));

        let mut retained = Operation { budget, poll };
        let mut types = Vec::<ParsedType>::new();
        for (ty, var, line) in borrowed {
            retained.checkpoint()?;
            if types.last().is_none_or(|previous| previous.path != ty) {
                kc::row(&mut retained, &mut types)?;
                types.push(ParsedType { path: kc::own(&mut retained, ty)?, fields: Vec::new() });
            }
            let fields = &mut types.last_mut().expect("current ordered map type").fields;
            kc::row(&mut retained, fields)?;
            fields.push((kc::own(&mut retained, var)?, line));
        }
        Ok(Self { types })
    }

    pub fn visit_storage(&self, mut visit: impl FnMut(usize, usize, usize)) {
        visit(self.types.as_ptr() as usize,
            self.types.len()*std::mem::size_of::<ParsedType>(),
            self.types.capacity()*std::mem::size_of::<ParsedType>());
        for ty in &self.types {
            visit(ty.path.as_ptr() as usize, ty.path.len(), ty.path.capacity());
            visit(ty.fields.as_ptr() as usize,
                ty.fields.len()*std::mem::size_of::<(String, usize)>(),
                ty.fields.capacity()*std::mem::size_of::<(String, usize)>());
            for (field, _) in &ty.fields {
                visit(field.as_ptr() as usize, field.len(), field.capacity());
            }
        }
    }

    pub fn edits(&self) -> impl Iterator<Item = (&str, &str, usize)> {
        self.types.iter().flat_map(|ty| ty.fields.iter().map(move |(var, line)| (ty.path.as_str(), var.as_str(), *line)))
    }
}

/// Policy input DATA only. A native caller must supply the original CODE_DM
/// sequence and actual legacy map discovery before publishing a full report.
#[derive(Default)]
pub struct CodeNames {
    parents: BTreeMap<String, (String, String)>,
    rows: BTreeMap<String, Vec<String>>,
    trait_vars: BTreeSet<String>,
    lazy_fields: BTreeSet<String>,
}

impl CodeNames {
    pub fn add_file<'a>(&mut self, relative: &str, lines: impl IntoIterator<Item = &'a str>) {
        match self.add_file_using(relative, lines, &mut Compatibility) {
            Ok(()) => {}, Err(never) => match never {},
        }
    }

    pub fn add_file_using<'a, C: Control>(
        &mut self, relative: &str, lines: impl IntoIterator<Item = &'a str>, control: &mut C,
    ) -> Result<(), C::Error> {
        control.checkpoint()?;
        if !CODE_DM.matches_path(relative) {
            return Ok(());
        }
        let variants = relative.starts_with("code/content/");
        let mut current = None;
        let mut in_state = false;
        let registry = crate::pat_match!(r#"^\t(/[\w/]+) = "(dq_variants_\w+)","#);
        let table = crate::pat_match!(r"^GLOBAL_LIST_INIT\((dq_variants_\w+), *list\(");
        let row = crate::pat_match!(r#"^\t"([^"]+)" = list\("#);
        let state_head = crate::pat_match!(r"^/datum/\w+_state\s*$");
        let state_var = crate::pat_match!(r"^\tvar/(?:\w+/)*(\w+)");
        for line in lines {
            control.checkpoint()?;
            if variants {
                if let Some(m) = registry.captures(line) {
                    let table = m.s(2);
                    if self.parents.get(table).is_none_or(|(old, _)| old.as_str() <= relative) {
                        let value = (kc::own(control, relative)?, kc::own(control, m.s(1))?);
                        if let Some(previous) = self.parents.get_mut(table) {
                            *previous = value;
                        } else {
                            kc::reserve(control, || Some(2048))?;
                            self.parents.insert(kc::own(control, table)?, value);
                        }
                    }
                } else if let Some(m) = table.captures(line) {
                    current = Some(m.s(1));
                } else if let (Some(name), Some(m)) = (current, row.captures(line)) {
                    if !self.rows.contains_key(name) {
                        kc::reserve(control, || Some(2048))?;
                        self.rows.insert(kc::own(control, name)?, Vec::new());
                    }
                    let rows = self.rows.get_mut(name).expect("current map alias table");
                    let key = kc::own(control, m.s(1))?;
                    if C::CHECKED { kc::row(control, rows)?; }
                    rows.push(key);
                } else if line.starts_with("))") {
                    current = None;
                }
            }
            if state_head.captures(line).is_some() {
                in_state = true;
                continue;
            }
            if in_state {
                if let Some(m) = state_var.captures(line) {
                    insert_text_set(&mut self.lazy_fields, m.s(1), control)?;
                } else if !line.starts_with('\t') && !line.trim().is_empty() {
                    in_state = false;
                }
            }
            if line.trim_start().starts_with("var_names = list(") {
                let body = line.trim_start().trim_start_matches("var_names = list(");
                for row in body.split(',') {
                    control.checkpoint()?;
                    if let Some((name, _)) = row.split_once('=') {
                        insert_text_set(&mut self.trait_vars, name.trim().trim_matches('"'), control)?;
                    }
                }
            }

        }
        control.checkpoint()
    }

    pub fn finish(self) -> Names {
        match self.finish_using(&mut Compatibility) { Ok(value) => value, Err(never) => match never {} }
    }

    pub fn finish_using<C: Control>(self, control: &mut C) -> Result<Names, C::Error> {
        let mut aliases = BTreeMap::new();
        for (table, (_, parent)) in self.parents {
            control.checkpoint()?;
            for key in self.rows.get(&table).into_iter().flatten() {
                let alias = kc::format(control, format_args!("{parent}/{key}"))?;
                // Preserve lexical table/row encounter overwrite semantics.
                insert_text_map(&mut aliases, &alias, &parent, control)?;
            }
        }
        control.checkpoint()?;
        Ok(Names { aliases, trait_vars: self.trait_vars, lazy_fields: self.lazy_fields })
    }
}

fn insert_text_set<C: Control>(set: &mut BTreeSet<String>, value: &str, control: &mut C) -> Result<(), C::Error> {
    if !set.contains(value) {
        // Same conservative per-node envelope as existing captured policy
        // ordered indexes, and charge the separate String backing before copy.
        kc::reserve(control, || Some(2048))?;
        set.insert(kc::own(control, value)?);
    }
    Ok(())
}

fn insert_text_map<C: Control>(map: &mut BTreeMap<String,String>, key: &str, value: &str, control: &mut C) -> Result<(), C::Error> {
    let value = kc::own(control, value)?;
    if let Some(existing) = map.get_mut(key) {
        *existing = value;
    } else {
        kc::reserve(control, || Some(2048))?;
        map.insert(kc::own(control, key)?, value);
    }
    Ok(())
}

pub struct Names {
    aliases: BTreeMap<String, String>,
    trait_vars: BTreeSet<String>,
    lazy_fields: BTreeSet<String>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Declaration {
    Variable,
    Type,
    Missing,
}

pub fn skips_map(relative: &str) -> bool {
    SKIP.iter().any(|prefix| relative.starts_with(prefix)) ||
        SKIP_NAMES.iter().any(|suffix| relative.ends_with(suffix))
}

impl Names {
    fn owner_for<'a>(&'a self, ty: &'a str, var: &str) -> Option<&'a str> {
        if MOVED.contains(&var) || self.trait_vars.contains(var) || self.lazy_fields.contains(var) {
            return None;
        }
        Some(self.aliases.get(ty).map(String::as_str).unwrap_or(ty))
    }

    /// Bounded native evaluation of already-parsed DATA. The caller must
    /// prove the CODE/maps source owners and matched semantic declaration role.
    /// Stage rows and publish only after this complete fold succeeds.
    pub fn append_map_using<C: Control>(
        &self, relative: &str, map: &ParsedMap,
        mut declaration: impl FnMut(&str, &str) -> Result<Declaration, C::Error>,
        out: &mut Vec<Site>, control: &mut C,
    ) -> Result<(), C::Error> {
        if skips_map(relative) {
            return control.checkpoint();
        }
        for (ty, var, number) in map.edits() {
            control.checkpoint()?;
            let Some(ty) = self.owner_for(ty, var) else { continue };
            let (rule, msg) = match declaration(ty, var)? {
                Declaration::Variable => continue,
                Declaration::Type => ("unknown_var", kc::format(control, format_args!("{ty}.{var}"))?),
                Declaration::Missing => ("unknown_type", kc::own(control, ty)?),
            };
            let line = u32::try_from(number).map_err(|_| control.overflow())?;
            let ident = kc::format(control, format_args!("{ty}::{var}"))?;
            // Sink::site_decl substitutes each control character with one
            // ASCII space. Same width, so use the already-funded String.
            let mut ident = ident.into_bytes();
            for byte in &mut ident {
                if matches!(*byte, b'\t' | b'\n' | b'\r') { *byte = b' '; }
            }
            let ident = String::from_utf8(ident).expect("ASCII replacement preserves valid UTF-8");
            if C::CHECKED { kc::row(control, out)?; }
            out.push(Site { rule: kc::own(control, rule)?, rel: kc::own(control, relative)?,
                line, msg, key: String::new(), ident });
        }
        control.checkpoint()
    }

    /// Uses the actual map bytes and the original lossy UTF-8 conversion.
    /// The caller owns admission and discards partial output on any failure.
    pub fn scan_map<E>(
        &self,
        relative: &str,
        bytes: &[u8],
        mut declaration: impl FnMut(&str, &str) -> Result<Declaration, E>,
        out: &mut Sink,
    ) -> Result<(), E> {
        if skips_map(relative) {
            return Ok(());
        }
        let text = String::from_utf8_lossy(bytes);
        for ((ty, var), number) in edits(&text) {
            let Some(ty) = self.owner_for(ty, var) else { continue };
            match declaration(ty, var)? {
                Declaration::Variable => {}
                Declaration::Type => out.site_decl(
                    "unknown_var", relative, number, format!("{ty}.{var}"), format!("{ty}::{var}"),
                ),
                Declaration::Missing => out.site_decl(
                    "unknown_type", relative, number, ty, format!("{ty}::{var}"),
                ),
            }
        }
        Ok(())
    }
}

#[cfg(feature = "native-policy")]
pub fn native_declaration(
    tree: &dm_tree::SemanticTree,
    proof: &dm_tree::checker_builtins::ValidatedCheckerProfile<'_>,
    profile: dm_ir::PackedU128,
    ty: &str,
    var: &str,
) -> Result<Declaration, String> {
    // Legacy Sem accepts slash (and empty) as root explicitly.
    if ty != "/" && !ty.is_empty() && !tree.checker_source_type_presence_validated(profile, ty, proof)
        .map_err(|error| format!("map edits type evidence: {error:?}"))? {
        return Ok(Declaration::Missing);
    }
    let owner = dm_ir::SymbolId::of(if ty.is_empty() { "/" } else { ty });
    Ok(if dm_analysis::checker_variable_facts::variable_original_validated(
        tree, proof, profile, owner, dm_ir::SymbolId::of(var),
    )?.is_some() {
        Declaration::Variable
    } else {
        Declaration::Type
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[cfg(feature = "native-policy")]
    #[test]
    fn bounded_map_edit_data_preserves_first_sorted_observations_and_denial() {
        use crate::{captured_generator_budget::Budget, captured_reactive_reads::Failure};
        let raw = b"/obj/b{same = first; z = 1}\r\n/obj/a{\r\nalpha = 2\r\n}\n/obj/b{same = \xff}\r\n/obj/b{same = again; a = 3}\n";
        let budget = Budget::new(128 * 1024).unwrap();
        let parsed = ParsedMap::parse(raw, &budget, &|| Ok(())).unwrap();
        assert_eq!(parsed.edits().collect::<Vec<_>>(), [
            ("/obj/a", "alpha", 3), ("/obj/b", "a", 6),
            ("/obj/b", "same", 1), ("/obj/b", "z", 1),
        ]);
        let parsed_rows = {
            let mut index = CodeNames::default();
            let mut control = crate::captured_allow_annotations::Operation { budget: &budget, poll: &|| Ok(()) };
            index.add_file_using("code/content/exempt_but_indexed.dm", ["\tvar_names = list(\"a\" = 1)"], &mut control).unwrap();
            let names = index.finish_using(&mut control).unwrap();
            let declare = |ty: &str, _: &str| Ok(if ty == "/obj/a" { Declaration::Type } else { Declaration::Missing });
            let mut rows = Vec::new();
            names.append_map_using("maps/actual.dmm", &parsed, declare, &mut rows, &mut control).unwrap();
            let mut legacy = Sink::default();
            names.scan_map("maps/actual.dmm", raw, declare, &mut legacy).unwrap();
            assert_eq!(serde_json::to_value(&rows).unwrap(), serde_json::to_value(&legacy.sites).unwrap());
            rows
        };
        assert_eq!(parsed_rows.len(), 3);
        let tiny = Budget::new(256).unwrap();
        assert!(matches!(ParsedMap::parse(raw, &tiny, &|| Ok(())),
            Err(Failure::Operational(error)) if error.kind() == std::io::ErrorKind::OutOfMemory));
        let cancelled = Budget::new(128 * 1024).unwrap();
        assert!(matches!(ParsedMap::parse(raw, &cancelled, &|| Err(std::io::Error::from_raw_os_error(1450))),
            Err(Failure::Operational(error)) if error.raw_os_error() == Some(1450)));
    }

    #[test]
    fn map_alias_registry_uses_legacy_slash_order_even_for_native_path_order() {
        let mut names = CodeNames::default();
        names.add_file("code/content/order/z.dm", ["\t/obj/last = \"dq_variants_fixture\","]);
        names.add_file("code/content/order-a.dm", [
            "\t/obj/first = \"dq_variants_fixture\",",
            "GLOBAL_LIST_INIT(dq_variants_fixture, list(",
            "\t\"ghost\" = list(",
            "))",
        ]);
        assert_eq!(names.finish().owner_for("/obj/last/ghost", "unknown"), Some("/obj/last"));
    }

    #[test]
    fn exact_alias_global_compatibility_and_map_scope_rows() {
        let mut names = CodeNames::default();
        names.add_file("code/content/a.dm", [
            "\t/obj/old = \"dq_variants_fixture\",",
            "GLOBAL_LIST_INIT(dq_variants_fixture, list(",
            "\t\"ghost\" = list(",
            "))",
        ]);
        names.add_file("code/content/z.dm", [
            "\t/obj/live = \"dq_variants_fixture\",",
            "/datum/sample_state",
            "\tvar/old_lazy",
            "/proc/unrelated()",
            "\tvar_names = list(\"old_trait\" = 1)",
        ]);
        names.add_file("code/content/.hidden/ignored.dm", [
            "\t/obj/wrong = \"dq_variants_fixture\",",
        ]);
        let names = names.finish();
        let bytes = b"/obj/live/ghost{existing = 1;bad = 2;old_lazy = 3}\r\n/obj/live/ghost{bad = 9}\r\n/unknown{old_trait = 4;emagged = 1;new = \"\xff\"}\r\n";
        let mut out = Sink::new();
        for relative in ["maps/palettes/test.dmm", "maps/fooSouthernCrossRef.dmm"] {
            names.scan_map::<()>(relative, bytes, |_, _| panic!("exempt map"), &mut out).unwrap();
        }
        names.scan_map::<()>("maps/.hidden/probe.dmm", bytes, |ty, var| Ok(match (ty, var) {
            ("/obj/live", "existing") => Declaration::Variable,
            ("/obj/live", "bad") => Declaration::Type,
            ("/unknown", "new") => Declaration::Missing,
            _ => panic!("unexpected semantic lookup {ty} {var}"),
        }), &mut out).unwrap();
        assert_eq!(out.sites.iter().map(|site| (site.rule.as_str(), site.rel.as_str(), site.line, site.msg.as_str(), site.ident.as_str(), site.key.as_str())).collect::<Vec<_>>(), [
            ("unknown_var", "maps/.hidden/probe.dmm", 1, "/obj/live.bad", "/obj/live::bad", ""),
            ("unknown_type", "maps/.hidden/probe.dmm", 3, "/unknown", "/unknown::new", ""),
        ]);
        assert!(out.allow_used.is_empty());
        assert!(out.notes.is_empty());
    }
}
