#[test]
fn storage_capacities_preserve_backing_and_canonical_bytes() {
    let mut words = Vec::with_capacity(19);
    words.extend_from_slice(&[17, 0]);
    let mut relocations = Vec::with_capacity(11);
    relocations.push(Relocation {
        offset: 1,
        reference: SymRef::String(SymbolId::of("payload")),
        encoding: RelocationEncoding::Direct,
    });
    let capacities = (words.capacity(), relocations.capacity());
    let compact = SymbolicCode::new(words.clone(), relocations.clone()).unwrap();
    let code = SymbolicCode::new(words, relocations).unwrap();
    assert_eq!(code.storage_capacities(), (capacities.0, 1));
    assert_eq!(code.canonical_bytes(), compact.canonical_bytes());
    assert_eq!(code.fingerprint(), compact.fingerprint());
}

use super::*;

#[test]
fn compact_sources_preserve_full_payloads_and_bidirectional_iteration() {
    assert_eq!(std::mem::size_of::<PackedSite>(), 12);
    let shared = SymRef::String(SymbolId::of("shared"));
    let refs = [
        SymRef::SourceFile(0),
        SymRef::SourceFile(u32::MAX),
        SymRef::SourceLine(u32::MAX),
        SymRef::LineDelta(u32::MAX),
        shared,
        shared,
    ];
    let expected: Vec<_> = refs
        .into_iter()
        .enumerate()
        .map(|(index, reference)| Relocation {
            offset: index as u32 * 2,
            reference,
            encoding: RelocationEncoding::PackedValue24 { tag: index as u8 },
        })
        .collect();
    let code = SymbolicCode::new(vec![0; 12], expected.clone()).unwrap();
    assert_eq!(code.reference_count(), 1);
    assert_eq!(code.relocations().collect::<Vec<_>>(), expected);
    let mut iter = code.relocations();
    assert_eq!(iter.len(), 6);
    assert_eq!(iter.next(), Some(expected[0]));
    assert_eq!(iter.next_back(), Some(expected[5]));
    assert_eq!(iter.len(), 4);
    assert_eq!(
        iter.rev().collect::<Vec<_>>(),
        expected[1..5].iter().rev().copied().collect::<Vec<_>>()
    );
    assert_eq!(code.relocation(6), None);
    let mut storage = Vec::new();
    code.visit_storage(|_, length, capacity| storage.push((length, capacity)));
    assert_eq!(storage[1], (72, 72));
    assert_eq!(
        storage[2],
        (std::mem::size_of::<SymRef>(), std::mem::size_of::<SymRef>())
    );
    let empty = SymbolicCode::new(Vec::new(), Vec::with_capacity(20)).unwrap();
    assert!(empty.relocations().is_empty());
    assert_eq!(empty.relocations().next_back(), None);
    assert_eq!(empty.storage_capacities(), (0, 0));
    assert_eq!(empty.reference_count(), 0);
}

#[test]
fn canonical_count_uses_exact_codec_for_every_reference_and_encoding() {
    let owner = SymbolId::of("/datum/sample");
    let name = SymbolId::of("sample");
    let procedure = crate::ProcedureIdentity {
        owner,
        name,
        verb: true,
        occurrence: 17,
    };
    let refs = [
        SymRef::String(name),
        SymRef::Type(owner),
        SymRef::Proc {
            owner,
            name,
            occurrence: 7,
        },
        SymRef::Verb {
            owner,
            name,
            occurrence: 8,
        },
        SymRef::Var { owner, name },
        SymRef::ArgumentSource {
            owner,
            name,
            verb: true,
            occurrence: 9,
            argument: 3,
        },
        SymRef::ProcedureStatic(crate::ProcedureStaticIdentity { procedure, name }),
        SymRef::VariableSlot(name),
        SymRef::BuiltinGlobalVars,
        SymRef::Instance(owner),
        SymRef::SourceFile(15),
        SymRef::SourceLine(42),
        SymRef::LineDelta(13),
        SymRef::ConstantList(71),
        SymRef::Resource(93),
    ];
    for reference in refs {
        for encoding in [
            RelocationEncoding::Direct,
            RelocationEncoding::PackedValue24 { tag: 6 },
            RelocationEncoding::PackedValue24 { tag: u8::MAX },
        ] {
            let code = SymbolicCode::new(
                vec![0; encoding.width() as usize],
                vec![Relocation {
                    offset: 0,
                    reference,
                    encoding,
                }],
            )
            .unwrap();
            let bytes = code.canonical_bytes();
            // Independent legacy framing: storage packing must not change
            // any reference variant, encoding byte or canonical identity.
            let mut legacy = b"dm-symbolic-code-v2\0".to_vec();
            legacy.extend_from_slice(&(encoding.width() as u64).to_le_bytes());
            for _ in 0..encoding.width() {
                legacy.extend_from_slice(&0u32.to_le_bytes());
            }
            legacy.extend_from_slice(&1u64.to_le_bytes());
            legacy.extend_from_slice(&0u32.to_le_bytes());
            match encoding {
                RelocationEncoding::Direct => legacy.push(0),
                RelocationEncoding::PackedValue24 { tag } => legacy.extend_from_slice(&[1, tag]),
            }
            encode_reference(
                &mut |chunk: &[u8]| legacy.extend_from_slice(chunk),
                reference,
            );
            assert_eq!(bytes, legacy);
            assert_eq!(code.canonical_len(), bytes.len());
            assert_eq!(code.fingerprint(), xxhash_rust::xxh3::xxh3_128(&bytes));
        }
    }
    let code = SymbolicCode::new(
        vec![0],
        vec![Relocation {
            offset: 0,
            reference: SymRef::BuiltinGlobalVars,
            encoding: RelocationEncoding::Direct,
        }],
    )
    .unwrap();
    let mut expected = b"dm-symbolic-code-v2\0".to_vec();
    expected.extend_from_slice(&1u64.to_le_bytes());
    expected.extend_from_slice(&0u32.to_le_bytes());
    expected.extend_from_slice(&1u64.to_le_bytes());
    expected.extend_from_slice(&0u32.to_le_bytes());
    expected.extend_from_slice(&[0, 6]);
    assert_eq!(code.canonical_bytes(), expected);
}
// Retain the original storage validator as an independent error-order oracle.
fn original_storage_validation(
    words: Vec<u32>,
    mut relocations: Vec<Relocation>,
) -> Result<SymbolicCode, RelocationError> {
    u32::try_from(words.len()).map_err(|_| RelocationError::WordCountOverflow)?;
    let mut seen = HashSet::new();
    for relocation in &relocations {
        for delta in 0..relocation.encoding.width() {
            let at = relocation
                .offset
                .checked_add(delta)
                .ok_or(RelocationError::OutOfBounds(relocation.offset))?;
            let word = words
                .get(at as usize)
                .ok_or(RelocationError::OutOfBounds(at))?;
            if !seen.insert(at) {
                return Err(RelocationError::Duplicate(at));
            }
            if *word != 0 {
                return Err(RelocationError::NonzeroPlaceholder(at));
            }
        }
    }
    relocations.sort_unstable_by_key(|relocation| relocation.offset);
    Ok(SymbolicCode::compact(
        crate::WordStorage::Owned(words),
        relocations,
    ))
}

#[test]
fn canonical_storage_fast_path_preserves_generic_errors_and_content() {
    let direct = RelocationEncoding::Direct;
    let packed = RelocationEncoding::PackedValue24 { tag: 6 };
    let site = |offset, encoding| Relocation {
        offset,
        reference: SymRef::String(SymbolId::of("text")),
        encoding,
    };
    let cases = [
        (vec![], vec![], None),
        (vec![0; 4], vec![site(0, packed), site(2, packed)], None),
        (vec![0; 4], vec![site(3, direct), site(0, packed)], None),
        (
            vec![0; 4],
            vec![site(0, packed), site(1, direct)],
            Some(RelocationError::Duplicate(1)),
        ),
        (
            vec![0; 4],
            vec![site(1, direct), site(0, packed)],
            Some(RelocationError::Duplicate(1)),
        ),
        (
            vec![1],
            vec![site(0, direct)],
            Some(RelocationError::NonzeroPlaceholder(0)),
        ),
        (
            vec![0, 1],
            vec![site(0, packed)],
            Some(RelocationError::NonzeroPlaceholder(1)),
        ),
        (
            vec![0],
            vec![site(0, packed)],
            Some(RelocationError::OutOfBounds(1)),
        ),
        (
            vec![0; 4],
            vec![site(u32::MAX, packed)],
            Some(RelocationError::OutOfBounds(u32::MAX)),
        ),
        (
            vec![1; 4],
            vec![site(0, direct), site(u32::MAX, packed)],
            Some(RelocationError::NonzeroPlaceholder(0)),
        ),
        (
            vec![1; 4],
            vec![site(4, direct), site(0, direct)],
            Some(RelocationError::OutOfBounds(4)),
        ),
    ];
    for (words, relocations, expected_error) in cases {
        let expected = original_storage_validation(words.clone(), relocations.clone());
        assert_eq!(expected.as_ref().err(), expected_error.as_ref());
        assert_eq!(SymbolicCode::new(words, relocations), expected);
    }
    // Both interval widths, both encounter orders, overlaps, out-of-bounds
    // and competing nonzero/duplicate failures, independent of golden cases.
    for bits in 0..16 {
        let words: Vec<_> = (0..4).map(|at| (bits >> at) & 1).collect();
        for left in 0..6 {
            for right in 0..6 {
                for encoding in [direct, packed] {
                    let relocations = vec![site(left, encoding), site(right, packed)];
                    assert_eq!(
                        SymbolicCode::new(words.clone(), relocations.clone()),
                        original_storage_validation(words.clone(), relocations)
                    );
                }
            }
        }
    }
}

#[test]
fn borrowed_site_ledgers_preserve_unsorted_validation_and_error_precedence() {
    let packed = RelocationEncoding::PackedValue24 { tag: 6 };
    let direct = RelocationEncoding::Direct;
    let code = SymbolicCode::new(
        vec![0; 6],
        vec![
            Relocation {
                offset: 3,
                reference: SymRef::BuiltinGlobalVars,
                encoding: direct,
            },
            Relocation {
                offset: 0,
                reference: SymRef::String(SymbolId::of("text")),
                encoding: packed,
            },
        ],
    )
    .unwrap();
    let string = RelocationKind::String;
    let variable = RelocationKind::Variable;
    let fixtures = [
        (vec![(3, variable, direct), (0, string, packed)], Ok(())),
        (
            vec![
                (3, string, direct),
                (0, variable, packed),
                (6, string, direct),
            ],
            Err(RelocationError::OutOfBounds(6)),
        ),
        (
            vec![(0, string, packed), (1, variable, direct)],
            Err(RelocationError::DuplicateSite(1)),
        ),
        (
            vec![(3, variable, direct)],
            Err(RelocationError::MissingSite(0)),
        ),
        (
            vec![(3, string, direct), (0, variable, packed)],
            Err(RelocationError::KindMismatch {
                offset: 0,
                expected: variable,
                actual: string,
            }),
        ),
        (
            vec![(3, variable, direct), (0, string, direct)],
            Err(RelocationError::EncodingMismatch(0)),
        ),
        (
            vec![
                (5, string, direct),
                (3, variable, direct),
                (2, string, direct),
                (0, string, packed),
            ],
            Err(RelocationError::MissingRelocation(2)),
        ),
    ];
    for (sites, expected) in fixtures {
        assert_eq!(code.validate_encoded_sites(&sites), expected);
        assert_eq!(
            code.validate_encoded_sites_iter(sites.iter().copied()),
            expected
        );
    }
}

#[test]
fn packed_values_validate_both_words_encoding_and_range() {
    let reference = SymRef::String(SymbolId::of("text"));
    let relocation = Relocation {
        offset: 0,
        reference,
        encoding: RelocationEncoding::PackedValue24 { tag: 6 },
    };
    assert_eq!(
        SymbolicCode::new(vec![0], vec![relocation]),
        Err(RelocationError::OutOfBounds(1))
    );
    assert_eq!(
        SymbolicCode::new(vec![0, 1], vec![relocation]),
        Err(RelocationError::NonzeroPlaceholder(1))
    );
    let overlapping = Relocation {
        offset: 1,
        reference,
        encoding: RelocationEncoding::Direct,
    };
    assert_eq!(
        SymbolicCode::new(vec![0, 0], vec![relocation, overlapping]),
        Err(RelocationError::Duplicate(1))
    );
    let code = SymbolicCode::new(vec![0, 0], vec![relocation]).unwrap();
    assert_eq!(
        code.validate_encoded_sites(&[(
            0,
            RelocationKind::String,
            RelocationEncoding::PackedValue24 { tag: 12 }
        )]),
        Err(RelocationError::EncodingMismatch(0))
    );
    assert_eq!(code.link(|_| Some(0x123456)).unwrap(), [0x1206, 0x3456]);
    assert_eq!(
        code.link(|_| Some(0x1000000)),
        Err(RelocationError::PackedValueOverflow {
            offset: 0,
            value: 0x1000000
        })
    );
    assert_eq!(code.words().as_ref(), [0, 0]);
    let different_tag = SymbolicCode::new(
        vec![0, 0],
        vec![Relocation {
            encoding: RelocationEncoding::PackedValue24 { tag: 12 },
            ..relocation
        }],
    )
    .unwrap();
    assert_ne!(code.fingerprint(), different_tag.fingerprint());
}

#[test]
fn typed_operand_sites_require_exact_reference_kinds() {
    let code = SymbolicCode::new(
        vec![42, 0],
        vec![Relocation {
            offset: 1,
            encoding: RelocationEncoding::Direct,
            reference: SymRef::BuiltinGlobalVars,
        }],
    )
    .unwrap();
    assert_eq!(
        code.validate_sites(&[(1, RelocationKind::Variable)]),
        Ok(())
    );
    assert_eq!(
        code.validate_sites(&[]),
        Err(RelocationError::MissingSite(1))
    );
    assert_eq!(
        code.validate_sites(&[(1, RelocationKind::String)]),
        Err(RelocationError::KindMismatch {
            offset: 1,
            expected: RelocationKind::String,
            actual: RelocationKind::Variable
        })
    );
    assert_eq!(
        code.validate_sites(&[(1, RelocationKind::Variable), (1, RelocationKind::Variable)]),
        Err(RelocationError::DuplicateSite(1))
    );
    assert_eq!(
        code.validate_sites(&[(2, RelocationKind::Variable)]),
        Err(RelocationError::OutOfBounds(2))
    );
    assert_eq!(
        SymbolicCode::new(vec![0], vec![])
            .unwrap()
            .validate_sites(&[(0, RelocationKind::String)]),
        Err(RelocationError::MissingRelocation(0))
    );
}

#[test]
fn fingerprints_preserve_namespace_and_canonicalize_site_order() {
    let owner = SymbolId::of("/datum/a");
    let name = SymbolId::of("read");
    let proc = SymRef::Proc {
        owner,
        name,
        occurrence: 0,
    };
    let verb = SymRef::Verb {
        owner,
        name,
        occurrence: 0,
    };
    let one = |reference| {
        SymbolicCode::new(
            vec![0],
            vec![Relocation {
                offset: 0,
                reference,
                encoding: RelocationEncoding::Direct,
            }],
        )
        .unwrap()
        .fingerprint()
    };
    assert_ne!(one(proc), one(verb));
    assert_ne!(one(SymRef::Type(owner)), one(SymRef::Instance(owner)));
    assert_ne!(
        one(SymRef::BuiltinGlobalVars),
        one(SymRef::VariableSlot(SymbolId::of("vars")))
    );
    let a = Relocation {
        offset: 0,
        encoding: RelocationEncoding::Direct,
        reference: proc,
    };
    let b = Relocation {
        offset: 1,
        encoding: RelocationEncoding::Direct,
        reference: SymRef::String(name),
    };
    assert_eq!(
        SymbolicCode::new(vec![0, 0], vec![a, b])
            .unwrap()
            .fingerprint(),
        SymbolicCode::new(vec![0, 0], vec![b, a])
            .unwrap()
            .fingerprint()
    );
}

#[test]
fn linking_separate_table_assignments_never_mutates_shared_words() {
    let symbol = SymRef::String(SymbolId::of("text"));
    let code = SymbolicCode::new(
        vec![99, 0, 0],
        vec![
            Relocation {
                offset: 2,
                encoding: RelocationEncoding::Direct,
                reference: SymRef::LineDelta(4),
            },
            Relocation {
                offset: 1,
                encoding: RelocationEncoding::Direct,
                reference: symbol,
            },
        ],
    )
    .unwrap();
    assert_eq!(
        code.link(|reference| Some(match reference {
            SymRef::String(_) => 7,
            SymRef::LineDelta(line) => 20 + line,
            _ => unreachable!(),
        }))
        .unwrap(),
        vec![99, 7, 24]
    );
    assert_eq!(
        code.link(|_| None),
        Err(RelocationError::Unresolved(symbol))
    );
    assert_eq!(code.link(|_| Some(3)).unwrap(), vec![99, 3, 3]);
    assert_eq!(code.words().as_ref(), [99, 0, 0]);
}

#[test]
fn malformed_relocation_tables_are_rejected_before_linking() {
    let relocation = Relocation {
        offset: 0,
        encoding: RelocationEncoding::Direct,
        reference: SymRef::LineDelta(0),
    };
    assert_eq!(
        SymbolicCode::new(vec![], vec![relocation]),
        Err(RelocationError::OutOfBounds(0))
    );
    assert_eq!(
        SymbolicCode::new(vec![0], vec![relocation, relocation]),
        Err(RelocationError::Duplicate(0))
    );
    assert_eq!(
        SymbolicCode::new(vec![1], vec![relocation]),
        Err(RelocationError::NonzeroPlaceholder(0))
    );
}

#[test]
fn shared_word_code_preserves_canonical_relocations_and_final_link_image() {
    let words = vec![99u32, 0, 17];
    let relocation = Relocation {
        offset: 1,
        reference: SymRef::String(SymbolId::of("mapped string")),
        encoding: RelocationEncoding::Direct,
    };
    let mut bytes = vec![255];
    for word in &words {
        bytes.extend_from_slice(&word.to_le_bytes());
    }
    let owner = std::sync::Arc::new(bytes);
    let weak = std::sync::Arc::downgrade(&owner);
    let storage = crate::WordStorage::shared(owner.clone(), 1..13).unwrap();
    let shared = SymbolicCode::from_word_storage(storage, vec![relocation]).unwrap();
    let owned = SymbolicCode::new(words, vec![relocation]).unwrap();
    assert_eq!(shared, owned);
    assert_eq!(shared.canonical_bytes(), owned.canonical_bytes());
    assert_eq!(shared.fingerprint(), owned.fingerprint());
    assert_eq!(shared.word_iter().collect::<Vec<_>>(), vec![99, 0, 17]);
    assert_eq!(shared.link(|_| Some(42)).unwrap(), vec![99, 42, 17]);
    assert_eq!(shared.word_at(1), Some(0));
    assert_eq!(
        shared.storage_capacities().0,
        0,
        "shared bytes are not a retained word Vec"
    );
    let mut buffers = Vec::new();
    shared.visit_storage(|address, len, capacity| buffers.push((address, len, capacity)));
    assert_eq!(
        buffers.len(),
        2,
        "word backing has its explicit shared storage descriptor"
    );
    assert!(matches!(
        shared.word_storage(),
        crate::WordStorageView::Shared { .. }
    ));
    drop(owner);
    assert!(weak.upgrade().is_some());
    drop(shared);
    assert!(weak.upgrade().is_none());
}
#[test]
fn shared_word_code_uses_same_placeholder_error_order_as_owned_code() {
    let owner = std::sync::Arc::new(vec![1, 0, 0, 0]);
    let storage = crate::WordStorage::shared(owner, 0..4).unwrap();
    let relocation = Relocation {
        offset: 0,
        reference: SymRef::String(SymbolId::of("bad placeholder")),
        encoding: RelocationEncoding::Direct,
    };
    assert_eq!(
        SymbolicCode::from_word_storage(storage, vec![relocation]).unwrap_err(),
        SymbolicCode::new(vec![1], vec![relocation]).unwrap_err()
    );
}
