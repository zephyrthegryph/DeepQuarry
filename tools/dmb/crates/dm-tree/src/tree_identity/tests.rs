use super::*;

pub(crate) fn legacy_identity(skeletons: &[Skeleton], fields: &[dm_ir::OpaqueFieldBase]) -> u128 {
    let mut bytes = Vec::new();
    bytes.extend_from_slice(b"dm-tree-v3\0");
    for skeleton in skeletons {
        match skeleton {
            Skeleton::Type {
                path,
                explicit_parent,
            } => {
                bytes.push(0);
                bytes.extend_from_slice(&path.bits().to_le_bytes());
                bytes.push(u8::from(explicit_parent.is_some()));
                bytes.extend_from_slice(
                    &explicit_parent
                        .map(SymbolId::bits)
                        .unwrap_or(0)
                        .to_le_bytes(),
                );
            }
            Skeleton::Member {
                owner,
                name,
                kind,
                mode,
                metadata,
                content,
            } => {
                bytes.push(1);
                bytes.extend_from_slice(&owner.bits().to_le_bytes());
                bytes.extend_from_slice(&name.bits().to_le_bytes());
                bytes.push(*kind as u8);
                bytes.push(*mode as u8);
                bytes.extend_from_slice(&content.to_le_bytes());
                bytes.extend_from_slice(&legacy_metadata(metadata).to_le_bytes());
            }
        }
    }
    let mut catalog = fields.iter().collect::<Vec<_>>();
    catalog.sort_by_key(|field| (field.owner, field.name));
    catalog.dedup();
    for field in catalog {
        let data = field.canonical_bytes();
        bytes.extend_from_slice(&(data.len() as u64).to_le_bytes());
        bytes.extend_from_slice(&data);
    }
    xxhash_rust::xxh3::xxh3_128(&bytes)
}
fn legacy_metadata(metadata: &MemberMetadata) -> u128 {
    let mut bytes = Vec::new();
    bytes.push(u8::from(metadata.inherited_opaque.is_some()));
    if let Some(base) = &metadata.inherited_opaque {
        bytes.extend_from_slice(&base.canonical_bytes());
    }
    for symbol in [
        metadata.declared_type,
        metadata.list_element_type,
        metadata.display_name,
    ] {
        bytes.push(u8::from(symbol.is_some()));
        bytes.extend_from_slice(&symbol.map(SymbolId::bits).unwrap_or(0).to_le_bytes());
    }
    bytes.push(u8::from(metadata.array.is_some()));
    if let Some(array) = &metadata.array {
        let data = array.canonical_bytes();
        bytes.extend_from_slice(&(data.len() as u64).to_le_bytes());
        bytes.extend_from_slice(&data);
    }
    bytes.push(u8::from(metadata.procedure.is_some()));
    if let Some(procedure) = &metadata.procedure {
        let value = procedure.canonical_bytes();
        bytes.extend_from_slice(&(value.len() as u64).to_le_bytes());
        bytes.extend_from_slice(&value);
    }
    bytes.push(u8::from(metadata.declared_initializer.is_some()));
    if let Some(initializer) = &metadata.declared_initializer {
        let data = initializer.canonical_bytes();
        bytes.extend_from_slice(&(data.len() as u64).to_le_bytes());
        bytes.extend_from_slice(&data);
    }
    bytes.push(u8::from(metadata.initializer.is_some()));
    if let Some(initializer) = &metadata.initializer {
        let data = initializer.canonical_bytes();
        bytes.extend_from_slice(&(data.len() as u64).to_le_bytes());
        bytes.extend_from_slice(&data);
    }
    bytes.push(u8::from(metadata.resolved_constant.is_some()));
    if let Some(value) = &metadata.resolved_constant {
        let data = value.canonical_bytes();
        bytes.extend_from_slice(&(data.len() as u64).to_le_bytes());
        bytes.extend_from_slice(&data);
    }
    bytes.extend_from_slice(&metadata.flags.to_le_bytes());
    bytes.extend_from_slice(&metadata.canonical);
    xxhash_rust::xxh3::xxh3_128(&bytes)
}

fn populated() -> MemberMetadata {
    let expression = SymbolicExpression {
        tokens: vec![ExpressionToken {
            kind: dm_syntax::TokenKind::Number,
            text: SymbolId::of("7"),
            relative_span: dm_syntax::Span::new(0, 1),
        }]
        .into(),
    };
    MemberMetadata {
        inherited_opaque: Some(dm_ir::OpaqueFieldBase {
            owner: SymbolId::of("/datum"),
            name: SymbolId::of("value"),
            declared_type: dm_ir::DeclaredTypeKnowledge::KnownUntyped,
        }),
        declared_type: Some(SymbolId::of("/datum")),
        list_element_type: Some(SymbolId::of("/obj")),
        display_name: Some(SymbolId::of("Display")),
        flags: u32::MAX,
        array: Some(Arc::new(dm_ir::ArrayDeclaration {
            dimensions: vec![None, Some(expression.clone())].into(),
            element_type: Some(SymbolId::of("/obj")),
        })),
        procedure: Some(Arc::new(ProcedureMetadata {
            signature: ProcedureSignature {
                parameters: Arc::from([]),
                variadic: true,
                return_annotation: Some(expression.clone()),
            },
            settings: vec![ProcedureSettingNode::Setting(ProcedureSetting {
                name: SymbolId::of("name"),
                operation: SettingOperation::In,
                value: expression.clone(),
            })]
            .into(),
        })),
        declared_initializer: Some(expression.clone()),
        initializer: Some(expression),
        resolved_constant: Some(SemanticValue::NumberBits((-1.25_f32).to_bits())),
        canonical: Arc::from(&b"exact\0canonical"[..]),
    }
}
#[test]
fn streaming_metadata_matches_independent_legacy_for_every_optional_combination() {
    for mask in 0..512 {
        let mut metadata = populated();
        if mask & 1 == 0 {
            metadata.inherited_opaque = None;
        }
        if mask & 2 == 0 {
            metadata.declared_type = None;
        }
        if mask & 4 == 0 {
            metadata.list_element_type = None;
        }
        if mask & 8 == 0 {
            metadata.display_name = None;
        }
        if mask & 16 == 0 {
            metadata.array = None;
        }
        if mask & 32 == 0 {
            metadata.procedure = None;
        }
        if mask & 64 == 0 {
            metadata.declared_initializer = None;
        }
        if mask & 128 == 0 {
            metadata.initializer = None;
        }
        if mask & 256 == 0 {
            metadata.resolved_constant = None;
        }
        assert_eq!(
            metadata_fingerprint(&metadata),
            legacy_metadata(&metadata),
            "mask={mask}"
        );
    }
    let metadata = populated();
    let original = metadata_fingerprint(&metadata);
    let mut changed = metadata.clone();
    changed.flags ^= 1;
    assert_ne!(original, metadata_fingerprint(&changed));
    changed = metadata.clone();
    changed.canonical = Arc::from(&b"changed"[..]);
    assert_ne!(original, metadata_fingerprint(&changed));
}
#[test]
fn streaming_tree_identity_preserves_domains_catalog_duplicates_and_source_order() {
    let field = dm_ir::OpaqueFieldBase {
        owner: SymbolId::of("/datum"),
        name: SymbolId::of("native"),
        declared_type: dm_ir::DeclaredTypeKnowledge::Known(SymbolId::of("/obj")),
    };
    let mut skeletons = vec![Skeleton::Type {
        path: SymbolId::of("/datum/base"),
        explicit_parent: Some(SymbolId::of("/datum")),
    }];
    for (index, (kind, mode)) in [
        (MemberKind::Var, DefinitionMode::Declare),
        (MemberKind::Proc, DefinitionMode::Override),
        (MemberKind::Verb, DefinitionMode::Implicit),
    ]
    .into_iter()
    .enumerate()
    {
        skeletons.push(Skeleton::Member {
            owner: SymbolId::of("/datum/base"),
            name: SymbolId::of(&format!("member{index}")),
            kind,
            mode,
            metadata: std::sync::Arc::new(populated()),
            content: index as u128,
        });
    }
    let fields = [field.clone(), field];
    assert_eq!(
        declaration_identity(&skeletons, &fields),
        legacy_identity(&skeletons, &fields)
    );
    assert_eq!(
        declaration_identity(&skeletons, &fields),
        declaration_identity(&skeletons, &fields[..1])
    );
    assert_eq!(declaration_identity(&[], &[]), legacy_identity(&[], &[]));
    let original = declaration_identity(&skeletons, &fields);
    skeletons.swap(1, 2);
    assert_ne!(original, declaration_identity(&skeletons, &fields));
    assert_eq!(
        declaration_identity(&skeletons, &fields),
        legacy_identity(&skeletons, &fields)
    );
}
