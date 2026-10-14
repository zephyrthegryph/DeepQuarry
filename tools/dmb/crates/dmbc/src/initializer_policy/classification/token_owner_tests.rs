//! Publication shares canonical bytes; token numbering remains serial.
use super::*;
#[test]
fn published_classifications_and_tokens_share_exact_prepublication_owner() {
    for debug in [false, true] {
        let mut symbols = SymbolTable::default();
        let a = write("list(1,2)", &mut symbols);
        let mut b = a.clone();
        b.target = InitializerTarget::Shared {
            slot: SymbolId::of("other.slot"),
            owner: symbols.intern("/").unwrap(),
            name: symbols.intern("other").unwrap(),
        };
        let mut appended = a.clone();
        appended.target = InitializerTarget::Shared {
            slot: SymbolId::of("appended.slot"),
            owner: symbols.intern("/").unwrap(),
            name: symbols.intern("appended").unwrap(),
        };
        let changed = write("list(1,3)", &mut symbols);
        let host = Host {
            value: AtomicU32::new(0),
            version: AtomicU64::new(1),
        };
        let store = InitializerArtifacts::default();
        let evaluator = crate::driver_facts::DriverEvaluator {
            pure_calls: None,
            resource_search_context: None,
            resolver: &host,
            symbols: &symbols,
        };
        let factory = evaluator.parallel_evaluator().unwrap();
        let reuse = InitializerReuse {
            store: &store,
            resolver: &host,
            policy: 1,
            resource_search_context: None,
        };
        let mut tokens = crate::initializer_policy::classification::token_owner::RequestTokens::new(
            debug,
            Some(&store.roster),
        );
        let prepare_key = |value: &InitializerWrite| {
            let mut locator = key(
                value,
                ModifierFact::Known(8),
                reuse,
                factory.factory.recording_policy_identity().unwrap(),
            );
            // These writes each occur once in their current source family.
            locator.extend_from_slice(&0u128.to_le_bytes());
            Arc::<[u8]>::from(locator)
        };
        let produce = |value: &InitializerWrite, ordinal| {
            let prepared = prepare_key(value);
            classify_one_keyed_grouped(
                value,
                &symbols,
                &evaluator,
                ModifierFact::Known(8),
                ordinal,
                factory,
                reuse,
                Some(&prepared),
                None,
                None,
                Some(&tokens),
            )
            .unwrap()
        };
        // Deliberately prepare in a different order from final source emission.
        let second = produce(&b, 1);
        let first = produce(&a, 0);
        let different = produce(&changed, 2);
        let first_owner = first
            .accepted
            .as_ref()
            .unwrap()
            .token_key()
            .unwrap()
            .clone();
        let second_owner = second
            .accepted
            .as_ref()
            .unwrap()
            .token_key()
            .unwrap()
            .clone();
        let different_owner = different
            .accepted
            .as_ref()
            .unwrap()
            .token_key()
            .unwrap()
            .clone();
        assert!(Arc::ptr_eq(&first_owner, &second_owner));
        assert!(!Arc::ptr_eq(&first_owner, &different_owner));
        assert!(Arc::ptr_eq(first.key.as_ref().unwrap(), &first_owner));
        let mut ordinal = 0;
        let output = store
            .roster
            .finish_shared(
                vec![first, second, different],
                debug,
                &mut ordinal,
                tokens.issuer(),
            )
            .unwrap();
        let values: Vec<_> = output
            .writes
            .iter()
            .map(|write| match &write.default {
                DefaultValue::InitializerExpression { token, canonical } => (*token, canonical),
                _ => panic!("constructor token required"),
            })
            .collect();
        assert!(Arc::ptr_eq(values[0].1, &first_owner));
        assert!(Arc::ptr_eq(values[1].1, &second_owner));
        assert!(Arc::ptr_eq(values[2].1, &different_owner));
        assert_eq!(values[0].0, 0);
        assert_eq!(values[1].0, if debug { 1 } else { 0 });
        assert_eq!(values[2].0, if debug { 2 } else { 1 });
        // Full construction bytes, not their locator, distinguish changed input.
        assert_ne!(values[0].1.as_ref(), values[2].1.as_ref());
        // A later new owner adopts the already published canonical bytes before
        // insertion, without mutating any previous classification.
        let mut next_tokens =
            crate::initializer_policy::classification::token_owner::RequestTokens::new(
                debug,
                Some(&store.roster),
            );
        let prepared = prepare_key(&appended);
        let added = classify_one_keyed_grouped(
            &appended,
            &symbols,
            &evaluator,
            ModifierFact::Known(8),
            3,
            factory,
            reuse,
            Some(&prepared),
            None,
            None,
            Some(&next_tokens),
        )
        .unwrap();
        assert!(Arc::ptr_eq(
            &first_owner,
            added.accepted.as_ref().unwrap().token_key().unwrap()
        ));
        // Prior numeric identities are never reused by the new request issuer.
        let (token, canonical) = next_tokens
            .issuer()
            .issue_shared(Arc::clone(&different_owner))
            .unwrap();
        assert_eq!(token, 0);
        assert!(Arc::ptr_eq(&canonical, &different_owner));
    }
}
