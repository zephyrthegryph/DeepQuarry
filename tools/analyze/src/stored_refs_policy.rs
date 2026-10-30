//! Original stored_refs metadata and raw policy projections, no typed model.
use crate::{
    lint::{Meta, Policy, RuleMeta, ScanKind},
    tree::CODE_DM,
};
const BASELINE: &str = "tools/ci/stored_refs_baseline.txt";

const H_VAR: &str = "declare the var: owns_one/ref_one/links()/slot() in the type's CAPABILITIES block (or its relations() table), which clears it when \
the other end is deleted; or keep a weak ref (ref_token(x), read back with resolve_token()). doc/rewrite/proposals/reference_storage.md";
const H_LIST: &str = "a list of atoms/datums is a declared many (owns_many/ref_many/a many links() end) or holds handles (ref_token(x)); a cache or \
pool keys by a handle or a type, never by the object. doc/rewrite/proposals/reference_storage.md";

pub(crate) static META: Meta = Meta {
    name: "stored_refs",
    group: "",
    label: "stored_refs",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Sites {
        baseline: BASELINE,
        header: &[
            "Stored references outside a declared relation or a weak ref (doc/rewrite/proposals/reference_storage.md). rule<TAB>file<TAB>text.",
            "`analyze check --lint stored_refs` fails on a site not listed here. Shrink-only: after a sweep run",
            "`analyze baseline --update --lint stored_refs`; it drops fixed sites and never adds one.",
        ],
        banned: &[],
    },
    rules: &[RuleMeta { name: "var", hint: H_VAR }, RuleMeta { name: "list", hint: H_LIST }],
    allow: &["stored_refs"],
    lists: &["exempt_types", "transient_types", "work_queues"],
};

pub fn metadata() -> &'static Meta {
    &META
}

#[cfg(feature = "native-policy")]
pub(crate) struct SourceFacts {
    pub relations: crate::relation_decl_policy::DeclarationIndex,
    pub schemas: crate::value_schema_policy::SchemaHints,
    pub init_only: Vec<(String, String)>,
    pub remaining: usize,
}
#[cfg(feature = "native-policy")]
impl SourceFacts {
    pub(crate) fn capture(
        raw: &crate::captured_raw_policy::CapturedRawPolicy,
        mut checkpoint: impl FnMut() -> Result<(), String>,
    ) -> Result<Self, String> {
        // Admit select + clone + sort scratch capacities before the FIRST Vec
        // allocation. This is coordination over borrowed owners, not a model.
        let roster_reserve = raw
            .tree
            .files
            .len()
            .checked_mul(std::mem::size_of::<&crate::tree::SourceFile>())
            .and_then(|n| n.checked_mul(8))
            .and_then(|n| n.checked_add(4096))
            .ok_or("stored source-roster admission overflow")?;
        if roster_reserve > 64 * 1024 * 1024 {
            return Err("stored source-roster exceeds admission before selection".into());
        }
        let files = raw.tree.select(&CODE_DM);
        let mut relations = crate::relation_decl_policy::declarations_with_registry_reserved(
            files.clone(),
            roster_reserve,
            &mut checkpoint,
        )?;
        let mut remaining = (64usize * 1024 * 1024)
            .checked_sub(relations.retained_admission)
            .ok_or("stored relation admission overflow")?;
        let header_reserve = files
            .iter()
            .map(|f| f.raw().text.len())
            .max()
            .unwrap_or(0)
            .checked_mul(2)
            .ok_or("stored header reserve overflow")?;
        remaining = remaining
            .checked_sub(header_reserve)
            .ok_or("stored header reserve admission exceeded")?;
        let mut schemas = crate::value_schema_policy::SchemaHints::default();
        let mut init_only = Vec::new();
        let keep = crate::pat!(r"(?m)^LIFECYCLE_KEEP_(?:UNLESS_FORCED|ALWAYS)\((/[\w/]+)\)");
        let head = crate::pat!(r"^CAPABILITIES\((/[\w/]+)\)");
        let param = crate::pat!(r"\bparam\(\s*nameof\((\w+)\).*\bkeep\s*=\s*FALSE");
        let successor = crate::pat!(r"\bsuccessor\s*=\s*nameof\((\w+)\)");
        for f in files {
            checkpoint()?;
            schemas.read_bounded_observed(f, &mut remaining, &mut checkpoint)?;
            let code = f.code();
            for c in keep.captures_iter(&code.text) {
                let ty = c.s(1);
                let charge = ty
                    .len()
                    .checked_mul(4)
                    .and_then(|n| n.checked_add(128))
                    .ok_or("stored keep-type admission overflow")?;
                remaining = remaining
                    .checked_sub(charge)
                    .ok_or("stored keep-type admission exceeded")?;
                relations.registry.push(ty.to_owned());
            }
            let mut owner: Option<String> = None;
            for line in code.lines() {
                checkpoint()?;
                if let Some(c) = head.captures(line) {
                    let ty = c.s(1);
                    if ty.len() > header_reserve {
                        return Err("stored init-header temporary admission exceeded".into());
                    }
                    owner = Some(ty.to_owned());
                    continue;
                }
                if !(line.starts_with('\t') || line.starts_with(' ')) && !line.trim().is_empty() {
                    owner = None;
                }
                if let Some(ty) = owner.as_deref() {
                    if let Some(c) = param.captures(line) {
                        put_pair(&mut init_only, ty, c.s(1), &mut remaining)?;
                    }
                    for c in successor.captures_iter(line) {
                        put_pair(&mut init_only, ty, c.s(1), &mut remaining)?;
                    }
                }
            }
        }
        checkpoint()?;
        if let Some(e) = raw.tree.captured_violation() {
            return Err(e);
        }
        Ok(Self {
            relations,
            schemas,
            init_only,
            remaining: remaining + header_reserve,
        })
    }
}
#[cfg(feature = "native-policy")]
fn put_pair(
    rows: &mut Vec<(String, String)>,
    owner: &str,
    name: &str,
    remaining: &mut usize,
) -> Result<(), String> {
    let charge = owner
        .len()
        .checked_add(name.len())
        .and_then(|n| n.checked_mul(4))
        .and_then(|n| n.checked_add(256))
        .ok_or("stored policy pair accounting overflow")?;
    *remaining = remaining
        .checked_sub(charge)
        .ok_or("stored policy pair admission exceeded before retention")?;
    rows.push((owner.to_owned(), name.to_owned()));
    Ok(())
}
