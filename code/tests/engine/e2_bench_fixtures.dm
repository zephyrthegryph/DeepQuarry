// The fixtures of the resolver benchmarks (code/modules/benchmarks/op_resolve.dm): a target with a 30-candidate stack.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/obj/item/e2_bench_key1
/obj/item/e2_bench_key2
/obj/item/e2_bench_key3
/obj/item/e2_bench_key4
/obj/item/e2_bench_key5
/obj/item/e2_bench_key6
/obj/item/e2_bench_key7
/obj/item/e2_bench_key8
/obj/item/e2_bench_key9
/obj/item/e2_bench_key10
/obj/item/e2_bench_key11
/obj/item/e2_bench_key12
/obj/item/e2_bench_key13
/obj/item/e2_bench_key14
/obj/item/e2_bench_key15
/obj/item/e2_bench_key16
/obj/item/e2_bench_key17
/obj/item/e2_bench_key18
/obj/item/e2_bench_key19
/obj/item/e2_bench_key20
/obj/item/e2_bench_key21
/obj/item/e2_bench_key22
/obj/item/e2_bench_key23
/obj/item/e2_bench_key24
/obj/item/e2_bench_key25
/obj/item/e2_bench_key26
/obj/item/e2_bench_key27
/obj/item/e2_bench_key28
/obj/item/e2_bench_key29
/obj/item/e2_bench_key30

/// The 30-candidate stack: one item(T) op per key type, and the empty hand.
/obj/e2_bench_stack
	name = "e2 bench stack"
	var/uses = 0

CAPABILITIES(/obj/e2_bench_stack, \
	op("hand_use", hand(), then(PROC_REF(note_use))), \
	op("key1", item(/obj/item/e2_bench_key1), then(PROC_REF(note_use))), \
	op("key2", item(/obj/item/e2_bench_key2), then(PROC_REF(note_use))), \
	op("key3", item(/obj/item/e2_bench_key3), then(PROC_REF(note_use))), \
	op("key4", item(/obj/item/e2_bench_key4), then(PROC_REF(note_use))), \
	op("key5", item(/obj/item/e2_bench_key5), then(PROC_REF(note_use))), \
	op("key6", item(/obj/item/e2_bench_key6), then(PROC_REF(note_use))), \
	op("key7", item(/obj/item/e2_bench_key7), then(PROC_REF(note_use))), \
	op("key8", item(/obj/item/e2_bench_key8), then(PROC_REF(note_use))), \
	op("key9", item(/obj/item/e2_bench_key9), then(PROC_REF(note_use))), \
	op("key10", item(/obj/item/e2_bench_key10), then(PROC_REF(note_use))), \
	op("key11", item(/obj/item/e2_bench_key11), then(PROC_REF(note_use))), \
	op("key12", item(/obj/item/e2_bench_key12), then(PROC_REF(note_use))), \
	op("key13", item(/obj/item/e2_bench_key13), then(PROC_REF(note_use))), \
	op("key14", item(/obj/item/e2_bench_key14), then(PROC_REF(note_use))), \
	op("key15", item(/obj/item/e2_bench_key15), then(PROC_REF(note_use))), \
	op("key16", item(/obj/item/e2_bench_key16), then(PROC_REF(note_use))), \
	op("key17", item(/obj/item/e2_bench_key17), then(PROC_REF(note_use))), \
	op("key18", item(/obj/item/e2_bench_key18), then(PROC_REF(note_use))), \
	op("key19", item(/obj/item/e2_bench_key19), then(PROC_REF(note_use))), \
	op("key20", item(/obj/item/e2_bench_key20), then(PROC_REF(note_use))), \
	op("key21", item(/obj/item/e2_bench_key21), then(PROC_REF(note_use))), \
	op("key22", item(/obj/item/e2_bench_key22), then(PROC_REF(note_use))), \
	op("key23", item(/obj/item/e2_bench_key23), then(PROC_REF(note_use))), \
	op("key24", item(/obj/item/e2_bench_key24), then(PROC_REF(note_use))), \
	op("key25", item(/obj/item/e2_bench_key25), then(PROC_REF(note_use))), \
	op("key26", item(/obj/item/e2_bench_key26), then(PROC_REF(note_use))), \
	op("key27", item(/obj/item/e2_bench_key27), then(PROC_REF(note_use))), \
	op("key28", item(/obj/item/e2_bench_key28), then(PROC_REF(note_use))), \
	op("key29", item(/obj/item/e2_bench_key29), then(PROC_REF(note_use))), \
	op("key30", item(/obj/item/e2_bench_key30), then(PROC_REF(note_use))))

/obj/e2_bench_stack/proc/note_use(datum/act/op/A)
	uses++
	return OP_OK

#endif
