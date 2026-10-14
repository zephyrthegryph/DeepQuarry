//! One current registration stream from the existing declaration allocation ledger.
use dm_ir::SymbolId;
use dm_link::{
    Entry, Key, LinkInventory, StringRegistration, StringRegistrationEvent as Event,
    StringRegistrationSource,
};
use dm_tree::{allocation_ledger::AllocationKind, frontend::ColdFrontend};
use std::{collections::HashSet, sync::Arc};
mod callable;

pub(crate) fn contribute_source_strings(
    frontend: &ColdFrontend,
    bodies: &dm_tree::frontend::BodyArena<'_>,
    inventory: &mut LinkInventory,
) -> Result<(), String> {
    if inventory.string_registration.is_some() {
        return Err("source string registrations supplied twice".into());
    }
    let names: HashSet<_> = frontend
        .allocation_ledger
        .events
        .iter()
        .filter_map(|event| match event.kind {
            AllocationKind::Field { name, .. } => Some(name),
            _ => None,
        })
        .collect();
    let mut existing: HashSet<_> = inventory
        .entry_iter()
        .filter_map(|entry| match entry.key {
            Key::String(id) => Some(id),
            _ => None,
        })
        .collect();
    let symbols = frontend.snapshot.tree.symbols();
    for &name in &names {
        let text = symbols.text(name).ok_or("source field spelling absent")?;
        // Keep collision validation in the ordinary numeric linker.
        if SymbolId::of(text) != name {
            return Err("source field spelling differs from symbolic identity".into());
        }
        let bytes: Arc<[u8]> = Arc::from(text.as_bytes());
        inventory.spellings.push((name, Arc::clone(&bytes)));
        if existing.insert(name) {
            inventory.entries.push(Entry {
                key: Key::String(name),
                content: bytes.into(),
            });
        }
    }
    let mut registration = StringRegistration::default();
    let mut first_root = false;
    for event in frontend.allocation_ledger.events.iter() {
        let source = StringRegistrationSource {
            encounter_order: event.encounter_order,
            expanded_start: event.span.start,
            expanded_end: event.span.end,
        };
        match event.kind {
            AllocationKind::Field {
                owner,
                name,
                initializer,
                ..
            } => {
                registration.events.push(Event::FieldName {
                    owner,
                    name,
                    source,
                });
                if let Some(span) = initializer {
                    let text = frontend.expanded.text.get(span.range()).ok_or(
                        "field initializer string registration lies outside current source",
                    )?;
                    let strings = candidate_literals(text, &names)?;
                    if !strings.is_empty() {
                        registration.events.push(Event::DeclarationStrings {
                            owner,
                            name,
                            strings: strings.into(),
                            source,
                        });
                    }
                }
            }
            AllocationKind::Procedure {
                owner,
                name,
                verb: false,
                body,
                ..
            } if owner == SymbolId::of("/") && !first_root => {
                first_root = true;
                let occurrence = frontend
                    .bodies
                    .iter()
                    .find(|occurrence| occurrence.expanded_span == body)
                    .ok_or("first root callable allocation has no current source occurrence")?;
                let input = frontend
                    .body_input(occurrence)
                    .map_err(|error| error.message)?;
                let identity = crate::lowering::source_unit_identity(frontend, occurrence)?;
                if identity.identity.owner != owner
                    || identity.identity.name != name
                    || identity.identity.namespace != crate::lowering::Namespace::Proc
                {
                    return Err(
                        "first root callable allocation differs from current callable identity"
                            .into(),
                    );
                }
                registration.events.push(Event::FirstRootCallable {
                    callable: crate::symbolic::unit_key(identity.identity),
                    declaration: occurrence.declaration.0,
                    strings: {
                        // A demand may borrow a previously parsed owner; the
                        // BodyArena's separate profile counts actual parses.
                        let _profile =
                            dm_profile::item("string_registration.first_root_body_demand");
                        bodies
                            .with_parsed(occurrence, |parsed| {
                                callable::registrations(frontend, &input, parsed, &names)
                            })
                            .map_err(|error| error.message)??
                            .into()
                    },
                    source,
                });
            }
            _ => {}
        }
    }
    inventory.string_registration = Some(registration);
    Ok(())
}

/// Stream existing lexical spans, retaining only candidate field spellings.
/// Unreachable/folded constant literals still register; other callable bodies
/// are never read. Nested interpolation literals use the same parsed expression
/// visitor and cooked decoder as emission, without evaluating any branches.
fn candidate_literals(text: &str, names: &HashSet<SymbolId>) -> Result<Vec<SymbolId>, String> {
    let mut seen = HashSet::new();
    Ok(candidate_literals_at(text, names, 0)?
        .into_iter()
        .filter_map(|(_, id)| seen.insert(id).then_some(id))
        .collect())
}

fn candidate_literals_at(
    text: &str,
    names: &HashSet<SymbolId>,
    base: usize,
) -> Result<Vec<(usize, SymbolId)>, String> {
    let mut strings = Vec::new();
    let mut error = None;
    let diagnostics = dm_syntax::visit_tokens(text, |token| {
        if token.kind != dm_syntax::TokenKind::String || error.is_some() {
            return;
        }
        if let Err(reason) =
            dm_codegen_byond::visit_constant_string_literals(token.text(text), |bytes| {
                let id = SymbolId::of_bytes(bytes);
                if names.contains(&id) {
                    match base.checked_add(token.span.start) {
                        Some(at) => strings.push((at, id)),
                        None => {
                            error = Some("string registration source coordinate overflow".into())
                        }
                    }
                }
            })
        {
            error = Some(reason);
        }
    });
    if let Some(error) = error {
        return Err(format!("source string registration: {error}"));
    }
    if let Some(error) = diagnostics.first() {
        return Err(format!("source string registration: {}", error.message));
    }
    Ok(strings)
}

#[cfg(test)]
mod tests;
