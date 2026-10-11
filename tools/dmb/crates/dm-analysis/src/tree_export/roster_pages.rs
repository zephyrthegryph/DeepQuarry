//! Bounded roster selectors from the same semantic export identity helpers.
use super::*;
#[derive(Clone, Copy)]
pub enum SemanticRoster {
    Types,
    Members,
    Intrinsics,
}
pub fn write_roster_page(
    tree: &SemanticTree,
    roster: SemanticRoster,
    start: u32,
    limit: u32,
    writer: &mut impl Write,
) -> Result<(), ExportError> {
    if !(1..=128).contains(&limit) {
        return Err(ExportError::InvalidModel(
            "semantic page limit must be 1..128",
        ));
    }
    let total = match roster {
        SemanticRoster::Types => tree.types().len(),
        SemanticRoster::Members => tree.members().len(),
        SemanticRoster::Intrinsics => tree.intrinsic_members().len(),
    };
    let total = u32::try_from(total)
        .map_err(|_| ExportError::InvalidModel("semantic roster exceeds u32"))?;
    if start > total {
        return Err(ExportError::InvalidModel(
            "semantic page cursor exceeds roster",
        ));
    }
    let end = start.saturating_add(limit).min(total);
    let symbols = tree.symbols();
    let mut items = Vec::with_capacity((end - start) as usize);
    for ordinal in start..end {
        items.push(match roster {
            SemanticRoster::Types => {
                let id=TypeId(ordinal);
                let node=tree.type_node(id).ok_or(ExportError::InvalidModel("unknown page type"))?;
                json!({"ordinal":ordinal,"row":"type","id":type_key(tree,id)?,
                    "path":spelling(symbols,node.path)?,"symbol":format!("{:016x}",node.path.bits()),
                    "parent":node.parent.map(|parent|type_key(tree,parent)).transpose()?,
                    "explicit_parent":node.explicit_parent,"synthetic":node.synthetic})
            }
            SemanticRoster::Intrinsics => {
                let member=&tree.intrinsic_members()[ordinal as usize];
                json!({"ordinal":ordinal,"row":"intrinsic_member","id":format!("intrinsic:{:016x}:{}:{:016x}",member.owner.bits(),kind(member.kind),member.name.bits()),
                    "owner_path":spelling(symbols,member.owner)?,"owner_symbol":format!("{:016x}",member.owner.bits()),
                    "name":symbols.text(member.name),"name_spelling_known":symbols.text(member.name).is_some(),"name_symbol":format!("{:016x}",member.name.bits()),"kind":kind(member.kind),
                    "provenance":"captured_engine_intrinsic_inventory","source_provenance_available":false,
                    "shared_owner":member.shared_owner.map(|owner|spelling(symbols,owner)).transpose()?,
                    "instance_storage_proven":member.instance_storage_proven,
                    "storage_status":if member.shared_owner.is_some() {"shared"} else if member.instance_storage_proven {"instance"} else {"unknown"}})
            }
            SemanticRoster::Members => {
                let id=dm_tree::MemberId(ordinal);
                let member=tree.member(id).ok_or(ExportError::InvalidModel("unknown page member"))?;
                let owner=tree.type_node(member.owner).ok_or(ExportError::InvalidModel("unknown page member owner"))?.path;
                let mut row=member_row::member_row(tree,id)?;
                let fields=row.as_object_mut().ok_or(ExportError::InvalidModel("invalid member row"))?;
                fields.insert("ordinal".into(),json!(ordinal));
                fields.insert("owner_path".into(),json!(spelling(symbols,owner)?));
                fields.insert("owner_symbol".into(),json!(format!("{:016x}",owner.bits())));
                fields.insert("name_symbol".into(),json!(format!("{:016x}",member.name.bits())));
                fields.insert("occurrence".into(),json!(tree.member_occurrence(id).ok_or(ExportError::InvalidModel("unknown page member occurrence"))?));
                fields.insert("previous_ordinal".into(),json!(member.previous.map(|id|id.0)));
                row
            }
        });
    }
    emit(
        writer,
        json!({"schema":"dm-session-semantic-page-v1","row":match roster {SemanticRoster::Types=>"semantic_types_page",SemanticRoster::Members=>"semantic_members_page",SemanticRoster::Intrinsics=>"semantic_intrinsic_members_page"},
        "revision":format!("{:032x}",tree.identity()),"complete":false,"page_complete":true,
        "coverage":"current semantic type, authored member-node or captured intrinsic roster selectors; inherited effective lookup is derived from parent links through the existing Resolver, not an expanded Cartesian roster; source/executable coverage excluded",
        "roster_scope":match roster {SemanticRoster::Types=>"semantic_type_nodes",SemanticRoster::Members=>"authored_member_nodes",SemanticRoster::Intrinsics=>"captured_engine_intrinsics"},
        "engine_intrinsic_members_included":matches!(roster,SemanticRoster::Intrinsics),"inherited_effective_members_included":false,
        "intrinsic_inventory_complete":tree.intrinsic_inventory_complete(),"hierarchy_certified":tree.intrinsic_hierarchy_certified(),
        "start":start,"limit":limit,"total":total,"returned":end-start,"next_cursor":if end<total {Some(end)} else {None},"items":items}),
    )
}
