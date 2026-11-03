//! Original player-link metadata and message; no semantic model required.
use crate::{
    lint::{Meta, Policy, RuleMeta, ScanKind},
    tree::CODE_DM,
};
const HINT: &str = "move a player with bind_player(mob, key) (or move_player() / transfer_mind() for a mind): the one place that writes mob.key and keeps the \
persistent client in step. doc/rewrite/proposals/relations.md D13";

pub(crate) static META: Meta = Meta {
    name: crate::allow_registry_fields::player_link::SCOPE_META_0.name,
    group: crate::allow_registry_fields::player_link::SCOPE_META_0.group,
    label: "player_link",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[RuleMeta {
        name: "raw_key",
        hint: HINT,
    }],
    allow: &[],
    lists: crate::allow_registry_fields::player_link::SCOPE_META_0.lists,
};

pub fn metadata() -> &'static Meta {
    &META
}
pub const MESSAGE: &str = "a raw write of a mob's key or ckey: use bind_player(mob, key)";
