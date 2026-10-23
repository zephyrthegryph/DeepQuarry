//! The order the global initializers run in, against programs measured with DreamMaker 516.1687: each case is a source
//! and the order DreamMaker's `<global-init>` stores the variables in (`startup_order` describes the rules).
use crate::startup_order::order;
use dm_tree::frontend::FrontendConfig;
use std::path::Path;

struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, path: &Path) -> Result<String, String> {
        if path.extension().is_some_and(|extension| extension == "dm") {
            Ok(self.0.into())
        } else {
            Ok("#include \"program.dm\"
"
            .into())
        }
    }
}

/// Any type path is a type: the programs name types, not their defaults.
struct AnyType;
impl crate::class_projection::TypeValuePolicy for AnyType {
    fn tag(&self, _: dm_ir::SymbolId) -> Result<u8, crate::class_projection::ProjectionError> {
        Ok(32)
    }
}

/// The variables `<global-init>` stores to, in code order, after a whole native compile.
fn global_init_order(source: &'static str) -> Result<Vec<String>, String> {
    let bytes = include_bytes!("../../../fixtures/native_template.bin");
    let mut host = crate::runner_host::BuildHost::default();
    let engine = host
        .engine(
            std::path::PathBuf::from("program.dme"),
            Default::default(),
            true,
            bytes.to_vec(),
        )
        .map_err(|error| format!("{error:?}"))?;
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let frontend = dm_tree::frontend::build_with_executor_and_semantic_state(
        Path::new("program.dme"),
        &Source(source),
        &Default::default(),
        FrontendConfig {
            workers: 1,
            engine: Some(engine.frontend_seed()),
            observer: None,
        },
        None,
        &executor,
        None,
    )
    .unwrap();
    let facts = host.host_facts();
    let (resolver, _scalar) = crate::request_runner::runner_facts::prepare_retained(
        &frontend,
        &engine,
        facts.as_deref(),
    )?;
    let output = crate::compile_driver::compile_observed_with_memo(
        &frontend,
        &resolver,
        &engine.snapshot,
        &engine.bytes,
        engine.link_overlay().unwrap(),
        &AnyType,
        None,
        Vec::new(),
        None,
        1,
        None,
        None,
    )
    .map_err(|error| format!("{error:?}"))?;
    let image = byond_dmb::dmb::Dmb::from_bytes(&output.dmb).unwrap();
    let initializer = image.world.ids[4];
    if initializer == 0xffff {
        return Ok(Vec::new());
    }
    let code = &image.lists[image.procs[initializer as usize].code_locals_args[0] as usize];
    Ok(byond_dmb::bytecode::decode(code)
        .unwrap()
        .iter()
        .filter(|instruction| instruction.name == "SetVar")
        .flat_map(|instruction| instruction.typed_operands().unwrap())
        .filter_map(|operand| match operand {
            byond_dmb::bytecode::Operand::Variable(byond_dmb::operands::Variable::Global(slot)) => {
                Some(
                    String::from_utf8_lossy(
                        image.string(image.variables[slot as usize].name).unwrap(),
                    )
                    .into_owned(),
                )
            }
            _ => None,
        })
        .collect())
}

const CASES: &[(&str, &str, &str)] = &[
    // p1: a parent sits among its children where its first member is
    ("p1", "/datum/p/c1/proc/x()\n\tvar/static/list/s_x = list(\"x\")\n/datum/p/proc/y()\n\tvar/static/list/s_y = list(\"y\")\n/datum/p/c2/proc/z()\n\tvar/static/list/s_z = list(\"z\")\n/datum/p/c1/proc/x2()\n\tvar/static/list/s_x2 = list(\"x2\")\n/datum/p/proc/y2()\n\tvar/static/list/s_y2 = list(\"y2\")\n", "s_x s_x2 s_y s_y2 s_z"),
    // p2: types by first member; a static var and a procedure of a type are members in source order
    ("p2", "/datum/p/c1/proc/x()\n\tvar/static/list/s_x = list(\"x\")\n/datum/p\n\tvar/static/list/v_p = list(\"vp\")\n/datum/p/c2\n\tvar/static/list/v_c2 = list(\"vc2\")\n/datum/p/c3/proc/w()\n\tvar/static/list/s_w = list(\"w\")\n/datum/p/c3\n\tvar/static/list/v_c3 = list(\"vc3\")\n/datum/p/c2/proc/z()\n\tvar/static/list/s_z = list(\"z\")\n/datum/p/c1\n\tvar/static/list/v_c1 = list(\"vc1\")\n", "s_x v_c1 v_p v_c2 s_z s_w v_c3"),
    // p5: a bare header, a parent_type assignment and an instance var touch a type
    ("p5", "/datum/p/c1\n/datum/p/c2\n\tvar/static/list/v_c2 = list(\"c2\")\n/datum/p/c3\n\tparent_type = /datum/p\n/datum/p/c4/proc/f4()\n\tvar/static/list/s_f4 = list(\"f4\")\n/datum/p/c3/proc/f3()\n\tvar/static/list/s_f3 = list(\"f3\")\n/datum/p/c1/proc/f1()\n\tvar/static/list/s_f1 = list(\"f1\")\n/datum/p/c5\n\tvar/v5 = 1\n/datum/p/c5/proc/f5()\n\tvar/static/list/s_f5 = list(\"f5\")\n/datum/p/proc/fp()\n\tvar/static/list/s_fp = list(\"fp\")\n", "s_f1 v_c2 s_f3 s_f4 s_f5 s_fp"),
    // p10: an override is a member of its own
    ("p10", "/datum/p/proc/base()\n\treturn 1\n/datum/p/proc/base2()\n\treturn 1\n/datum/p/c1/proc/d1()\n\tvar/static/list/s_d1 = list(\"d1\")\n/datum/p/c1/base()\n\tvar/static/list/s_o1 = list(\"o1\")\n/datum/p/c2/base()\n\tvar/static/list/s_o2 = list(\"o2\")\n/datum/p/c2/proc/d2()\n\tvar/static/list/s_d2 = list(\"d2\")\n/datum/p/base2()\n\tvar/static/list/s_op = list(\"op\")\n/datum/p/c3/proc/d3()\n\tvar/static/list/s_d3 = list(\"d3\")\n", "s_d1 s_o1 s_o2 s_d2 s_op s_d3"),
    // p11: declarations of a type are one member, overrides follow in order
    ("p11", "/datum/p/proc/base()\n\treturn 1\n/datum/p/c1/proc/d1()\n\tvar/static/list/s_d1 = list(\"d1\")\n/datum/p/c2/base()\n\tvar/static/list/s_o2 = list(\"o2\")\n/datum/p/c1/base()\n\tvar/static/list/s_o1 = list(\"o1\")\n/datum/p/c2/proc/d2()\n\tvar/static/list/s_d2 = list(\"d2\")\n/datum/p/c1/proc/d1b()\n\tvar/static/list/s_d1b = list(\"d1b\")\n", "s_d1 s_d1b s_o1 s_o2 s_d2"),
    // p12: a bare header orders types
    ("p12", "/datum/p/c1\n\tvar/inst = 1\n/datum/p/c2/proc/f2()\n\tvar/static/list/s_c2 = list(\"c2\")\n/datum/p/c3\n/datum/p/c4/proc/f4()\n\tvar/static/list/s_c4 = list(\"c4\")\n/datum/p/c1/proc/f1()\n\tvar/static/list/s_c1 = list(\"c1\")\n/datum/p/c3/proc/f3()\n\tvar/static/list/s_c3 = list(\"c3\")\n", "s_c1 s_c2 s_c3 s_c4"),
    // p13: a bare header and static vars order types
    ("p13", "/datum/p/c1\n\tvar/inst = 1\n/datum/p/c2/proc/f2()\n\tvar/static/list/s_c2 = list(\"c2\")\n/datum/p/c3\n\tvar/static/list/v_c3 = list(\"v3\")\n/datum/p/c4/proc/f4()\n\tvar/static/list/s_c4 = list(\"c4\")\n/datum/p/c1\n\tvar/static/list/v_c1 = list(\"v1\")\n/datum/p/c1/proc/f1()\n\tvar/static/list/s_c1 = list(\"c1\")\n/datum/p/c3/proc/f3()\n\tvar/static/list/s_c3 = list(\"c3\")\n", "v_c1 s_c1 s_c2 v_c3 s_c3 s_c4"),
    // p14: an override before its declaration touches the type
    ("p14", "/datum/p/c1/base1()\n\tvar/static/list/s_c1_o = list(\"x\")\n/datum/p/c2/proc/dc2()\n\tvar/static/list/s_c2_d = list(\"x\")\n/datum/p/c1/proc/dc1()\n\tvar/static/list/s_c1_d = list(\"x\")\n/datum/p/proc/base1()\n\treturn 1\n", "s_c1_o s_c1_d s_c2_d"),
    // p15: an override after its declaration touches the type
    ("p15", "/datum/p/proc/base1()\n\treturn 1\n/datum/p/c1/base1()\n\tvar/static/list/s_c1_o = list(\"x\")\n/datum/p/c2/proc/dc2()\n\tvar/static/list/s_c2_d = list(\"x\")\n/datum/p/c1/proc/dc1()\n\tvar/static/list/s_c1_d = list(\"x\")\n", "s_c1_o s_c1_d s_c2_d"),
    // p17: builtin roots
    ("p17", "/datum/qa\n\tvar/static/list/b01_datum = list(\"a\")\n/obj/qb\n\tvar/static/list/b02_obj = list(\"a\")\n/mob/qc\n\tvar/static/list/b03_mob = list(\"a\")\n/turf/qd\n\tvar/static/list/b04_turf = list(\"a\")\n/turf/simulated/qe\n\tvar/static/list/b05_turf_sim = list(\"a\")\n/area/qf\n\tvar/static/list/b06_area = list(\"a\")\n/atom/movable/qg\n\tvar/static/list/b07_movable = list(\"a\")\n/obj/item/qh\n\tvar/static/list/b08_item = list(\"a\")\n/image/qi\n\tvar/static/list/b09_image = list(\"a\")\n/client/qj\n\tvar/static/list/b10_client = list(\"a\")\n/turf/simulated/wall/qk\n\tvar/static/list/b11_deep = list(\"a\")\n", "b01_datum b02_obj b08_item b03_mob b04_turf b05_turf_sim b11_deep b06_area b07_movable b09_image b10_client"),
    // p18: same-named statics and globals
    ("p18", "var/list/g_zz = list(1)\nvar/list/g_late = list(2)\n/datum/q/proc/f()\n\tvar/static/list/g_zz = list(\"a\")\n\tvar/static/list/b01_plain = list(\"a\")\n\tvar/static/list/g_fwd = list(\"b\")\n/datum/q2/proc/f2()\n\tvar/static/list/g_late = list(\"a\")\nvar/list/g_fwd = list(3)\n/datum/q3\n\tvar/static/list/g_zz = list(\"c\")\n\tvar/static/list/g_late2 = list(\"c\")\nvar/list/g_late2 = list(4)\n", "g_zz g_late g_zz b01_plain g_fwd g_late g_zz g_late2 g_fwd g_late2"),
    // p19: reparented types
    ("p19", "/datum/pa\n\tvar/static/list/b00_pa = list(\"a\")\n/datum/pb\n\tparent_type = /datum/pa\n\tvar/static/list/b01_reparented = list(\"a\")\n/datum/pb/proc/f()\n\tvar/static/list/b02_reparented_proc = list(\"a\")\n/datum/pc\n\tvar/static/list/b03_after = list(\"a\")\n/datum/pd/pe\n\tparent_type = /datum/pc\n\tvar/static/list/b04_child_reparented = list(\"a\")\n/datum/pd/pe/proc/g()\n\tvar/static/list/b05_child_proc = list(\"a\")\n", "b00_pa b01_reparented b02_reparented_proc b03_after b04_child_reparented b05_child_proc"),
    // p21: statics named like instance variables
    ("p21", "/datum/other\n\tvar/list/has_x = list()\n\tvar/hy = 1\n/datum/q/proc/f()\n\tvar/static/list/has_x = list(\"a\")\n\tvar/static/list/b01_plain = list(\"b\")\n\tvar/static/list/hy = list(\"c\")\n/datum/q2/proc/g()\n\tvar/static/list/has_x = list(\"a\")\n/datum/late\n\tvar/list/has_z = list()\n/datum/q/proc/h()\n\tvar/static/list/has_z = list(\"z\")\n", "has_x b01_plain hy has_z has_x"),
    // p24: a call of a global procedure before any global procedure was walked
    ("p24", "/datum/q/proc/f()\n\tvar/static/b19_call = fcall(1)\n\tvar/static/b20_call2 = fcall2()\n/proc/fcall(a)\n\treturn a\n/proc/fcall2()\n\treturn 1\n", "b19_call b20_call2"),
    // p26: a call of a global procedure after one was walked
    ("p26", "/proc/h_other()\n\treturn 1\n/datum/q/proc/f()\n\tvar/static/b19_call = fcall(1)\n/proc/fcall(a)\n\treturn a\n", "b19_call"),
    // p27: a type procedure does not count as a global procedure
    ("p27", "/datum/pp/proc/zzz()\n\treturn 1\n/datum/q/proc/f()\n\tvar/static/b19_call = fcall(1)\n/proc/fcall(a)\n\treturn a\n", "b19_call"),
    // p30: parent_type of a type defined first
    ("p30", "/turf/open\n\tvar/static/list/b00_open = list(\"o\")\n/turf/simulated\n\tparent_type = /turf/open\n\tvar/static/list/b01_sim = list(\"s\")\n/turf/simulated/wall\n\tvar/static/list/b02_wall = list(\"w\")\n/turf/simulated/wall/proc/gwc()\n\tvar/static/list/b03_wall_proc = list(\"0\")\n/turf/simulated/floor\n\tvar/static/list/b04_floor = list(\"f\")\n/turf/other\n\tvar/static/list/b05_other = list(\"x\")\n/obj/item/zz\n\tvar/static/list/b06_item = list(\"i\")\n", "b00_open b01_sim b02_wall b03_wall_proc b04_floor b05_other b06_item"),
    // p31: parent_type of a type defined first, children before
    ("p31", "/turf/open\n\tvar/static/list/b00_open = list(\"o\")\n/turf/simulated/wall\n\tvar/static/list/b02_wall = list(\"w\")\n/turf/simulated/wall/proc/gwc()\n\tvar/static/list/b03_wall_proc = list(\"0\")\n/turf/simulated/floor\n\tvar/static/list/b04_floor = list(\"f\")\n/turf/other\n\tvar/static/list/b05_other = list(\"x\")\n/turf/simulated\n\tparent_type = /turf/open\n\tvar/static/list/b01_sim = list(\"s\")\n/obj/item/zz\n\tvar/static/list/b06_item = list(\"i\")\n", "b00_open b02_wall b03_wall_proc b04_floor b01_sim b05_other b06_item"),
    // p32: a late subtree is walked after the first pass
    ("p32", "/turf/simulated\n\tparent_type = /turf/open\n\tvar/static/list/b01_sim = list(\"s\")\n/turf/simulated/wall\n\tvar/static/list/b02_wall = list(\"w\")\n/turf/simulated/wall/proc/gwc()\n\tvar/static/list/b03_wall_proc = list(\"0\")\n/turf/other\n\tvar/static/list/b05_other = list(\"x\")\n/obj/item/zz\n\tvar/static/list/b06_item = list(\"i\")\n/turf/open\n\tvar/static/list/b00_open = list(\"o\")\n", "b05_other b00_open b06_item b01_sim b02_wall b03_wall_proc"),
    // p42: late parents chain
    ("p42", "/datum/late1\n\tparent_type = /datum/zzz\n\tvar/static/list/b01_late1 = list(\"1\")\n/datum/late2\n\tparent_type = /datum/late1\n\tvar/static/list/b02_late2 = list(\"2\")\n/datum/late3\n\tparent_type = /datum/late1/child\n\tvar/static/list/b03_late3 = list(\"3\")\n/datum/late1/child\n\tvar/static/list/b04_late1_child = list(\"4\")\n/datum/plain\n\tvar/static/list/b05_plain = list(\"5\")\n/datum/zzz\n\tvar/static/list/b06_zzz = list(\"6\")\n/datum/late4\n\tparent_type = /datum/plain\n\tvar/static/list/b07_late4 = list(\"7\")\n/datum/late5\n\tparent_type = /datum/zzz\n\tvar/static/list/b08_late5 = list(\"8\")\n", "b05_plain b06_zzz b07_late4 b08_late5 b01_late1 b04_late1_child b02_late2 b03_late3"),
    // p43: nameof of type members and statics of the same procedure
    ("p43", "/datum/q\n\tvar/vv = 1\n/datum/q/proc/f()\n\tvar/static/b01_nameof_type_vv = nameof(type::vv)\n\tvar/static/list/b02_list = list(nameof(type::vv))\n\tvar/static/b03_plain = 1\n\tvar/static/b04_ref_prev = b03_plain\n\tvar/static/b05_ref_prev_late = b06_late_ref\n\tvar/static/b06_late_ref = world.time\n\tvar/static/b07_ref_late = b06_late_ref\n\tvar/static/list/b08_listref = list(b03_plain)\n\tvar/static/list/b09_listref_late = list(b06_late_ref)\n", "b04_ref_prev b08_listref b02_list b06_late_ref b07_ref_late b09_listref_late b05_ref_prev_late"),
    // p6: type references resolve once the type was walked
    ("p6", "/datum/early1\n\tvar/x = 1\n/datum/early2/proc/foo()\n\treturn 1\n/datum/q/proc/f()\n\tvar/static/s1_early_type = list(/datum/early1)\n\tvar/static/s2_early_type2 = list(/datum/early2)\n\tvar/static/s3_late_type = list(/datum/late1)\n\tvar/static/s4_self = list(/datum/q)\n\tvar/static/s5_newearly = new /datum/early1()\n\tvar/static/s6_newlate = new /datum/late1()\n\tvar/static/s7_str = list(\"a\")\n/datum/q\n\tvar/static/list/v1_early_type = list(/datum/early1)\n\tvar/static/list/v2_late_type = list(/datum/late1)\n\tvar/static/list/v3_str = list(\"a\")\n\tvar/static/v4_new = new /datum/early1()\n/datum/late1\n\tvar/y = 2\n", "s1_early_type s2_early_type2 s5_newearly s7_str v1_early_type v3_str v4_new s3_late_type s4_self s6_newlate v2_late_type"),
    // p8: type path references
    ("p8", "/datum/aa/bb/proc/x()\n\treturn 1\n/datum/hh\n/datum/pp\n\tparent_type = /datum/aa\n/datum/q/proc/f()\n\tvar/static/b1_builtin_datum = /datum\n\tvar/static/b2_anc_only = /datum/aa\n\tvar/static/b3_leaf = /datum/aa/bb\n\tvar/static/b4_bare_header = /datum/hh\n\tvar/static/b5_parent_assign = /datum/pp\n\tvar/static/b6_obj = /obj\n\tvar/static/b7_mobtype = /mob\n\tvar/static/b8_later_sub = /datum/zz\n/datum/q\n\tvar/static/c1_self = /datum/q\n\tvar/static/c2_self_proc = /datum/q/proc/f\n/datum/q2\n\tvar/mm = 1\n\tvar/static/c3_self_in_own_first_block = /datum/q2\n\tvar/static/c4_after = /datum/q3\n/datum/q3\n\tvar/nn = 1\n/datum/zz/yy\n\tvar/oo = 1\n", ""),
];

#[test]
fn global_initializers_run_in_the_order_dreammaker_allocates_them() {
    let mut failures = Vec::new();
    for (name, source, expected) in CASES {
        let got = match global_init_order(source) {
            Ok(got) => got.join(" "),
            Err(error) => {
                failures.push(format!("{name}: {error}"));
                continue;
            }
        };
        if got != *expected {
            failures.push(format!("{name}:\n  expected {expected}\n  got      {got}"));
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

#[test]
fn an_empty_program_has_no_initializer_order() {
    assert!(order(&[], &[], &dm_ir::SymbolTable::default()).is_empty());
}

mod synthetic {
    use crate::startup_order::{order, EventKind, OrderEvent, OrderWrite, Ref};
    use dm_ir::{SymbolId, SymbolTable};

    /// Events and initializers by hand, for the rules a whole compile cannot show on a small program.
    struct Program {
        symbols: SymbolTable,
        events: Vec<OrderEvent>,
        writes: Vec<OrderWrite>,
    }
    impl Program {
        fn new() -> Self {
            let mut symbols = SymbolTable::default();
            symbols.intern("/").unwrap();
            Self {
                symbols,
                events: Vec::new(),
                writes: Vec::new(),
            }
        }
        fn id(&mut self, text: &str) -> SymbolId {
            // The ledger interns every prefix of a path.
            for (at, _) in text.match_indices('/').skip(1) {
                self.symbols.intern(&text[..at]).unwrap();
            }
            self.symbols.intern(text).unwrap()
        }
        fn event(
            &mut self,
            kind: EventKind,
            owner: &str,
            name: &str,
            formal: bool,
            target: Option<&str>,
        ) -> u32 {
            let owner = self.id(owner);
            let name = self.id(name);
            let target = target.map(|target| self.id(target));
            self.events.push(OrderEvent {
                kind,
                owner,
                name,
                formal,
                verb: false,
                target,
            });
            self.events.len() as u32 - 1
        }
        fn field(&mut self, owner: &str, name: &str) -> u32 {
            self.event(EventKind::Field, owner, name, false, None)
        }
        fn procedure(&mut self, owner: &str, name: &str) -> u32 {
            self.event(EventKind::Procedure, owner, name, true, None)
        }
        fn write(
            &mut self,
            event: u32,
            procedure_static: bool,
            owner: &str,
            name: &str,
            refs: Vec<Ref>,
        ) -> u32 {
            let owner = self.id(owner);
            let name = self.id(name);
            self.writes.push(OrderWrite {
                event,
                procedure_static,
                owner,
                name,
                refs,
                world: false,
            });
            self.writes.len() as u32 - 1
        }
        fn order(&self) -> Vec<u32> {
            order(&self.events, &self.writes, &self.symbols)
        }
    }

    #[test]
    fn a_global_walked_after_the_type_waits_for_the_next_pass() {
        // /datum/q is named first, so its subtree is walked before the global declared after it; the static that
        // reads the global waits (measured: DreamMaker allocates it after the initializer of the later global).
        let mut p = Program::new();
        p.field("/datum/q", "touch");
        p.field("/", "g_mid");
        let procedure = p.procedure("/datum/q", "f");
        let other = p.field("/", "other");
        let g_mid = p.id("g_mid");
        let reads = p.write(
            procedure,
            true,
            "/datum/q",
            "reads",
            vec![Ref::Ident(g_mid)],
        );
        let later = p.write(other, false, "/", "other", Vec::new());
        assert_eq!(p.order(), vec![later, reads]);
    }

    #[test]
    fn a_late_subtree_is_walked_from_the_second_pass() {
        // `parent_type = /turf/open` names a type that does not exist yet: /turf/simulated is late.
        let mut p = Program::new();
        p.event(
            EventKind::Parent,
            "/turf/simulated",
            "",
            false,
            Some("/turf/open"),
        );
        let simulated = p.field("/turf/simulated", "s1");
        let plain = p.field("/datum/m", "s2");
        let open = p.field("/turf/open", "o");
        let w_simulated = p.write(simulated, false, "/turf/simulated", "s1", Vec::new());
        let w_plain = p.write(plain, false, "/datum/m", "s2", Vec::new());
        let w_open = p.write(open, false, "/turf/open", "o", Vec::new());
        assert_eq!(p.order(), vec![w_open, w_plain, w_simulated]);
    }

    #[test]
    fn a_target_that_exists_makes_a_type_ordinary() {
        let mut p = Program::new();
        let open = p.field("/turf/open", "o");
        p.event(
            EventKind::Parent,
            "/turf/simulated",
            "",
            false,
            Some("/turf/open"),
        );
        let simulated = p.field("/turf/simulated", "s1");
        let w_open = p.write(open, false, "/turf/open", "o", Vec::new());
        let w_simulated = p.write(simulated, false, "/turf/simulated", "s1", Vec::new());
        assert_eq!(p.order(), vec![w_open, w_simulated]);
    }

    #[test]
    fn a_reference_into_a_late_subtree_waits_until_it_was_walked() {
        let mut p = Program::new();
        p.event(
            EventKind::Parent,
            "/turf/simulated",
            "",
            false,
            Some("/turf/open"),
        );
        let simulated = p.field("/turf/simulated", "s1");
        let main = p.field("/datum/m", "reads_late");
        let open = p.field("/turf/open", "o");
        let late = p.id("/turf/simulated");
        let w_simulated = p.write(simulated, false, "/turf/simulated", "s1", Vec::new());
        let w_main = p.write(main, false, "/datum/m", "reads_late", vec![Ref::Type(late)]);
        let w_open = p.write(open, false, "/turf/open", "o", Vec::new());
        // Pass 1: /turf/open. Pass 2: the late subtree first (its key is smaller), then /datum/m, which now resolves.
        assert_eq!(p.order(), vec![w_open, w_simulated, w_main]);
    }

    #[test]
    fn a_call_of_a_global_procedure_needs_one_walked_first() {
        let mut p = Program::new();
        let first = p.field("/datum/q", "first");
        let plain = p.field("/datum/q", "plain");
        p.procedure("/", "fcall");
        let fcall = p.id("fcall");
        let w_call = p.write(first, false, "/datum/q", "first", vec![Ref::Call(fcall)]);
        let w_plain = p.write(plain, false, "/datum/q", "plain", Vec::new());
        // No global procedure was walked when the first runs its call: it waits, the plain one does not.
        assert_eq!(p.order(), vec![w_plain, w_call]);
        let mut p = Program::new();
        p.procedure("/", "fcall");
        let first = p.field("/datum/q", "first");
        let plain = p.field("/datum/q", "plain");
        let fcall = p.id("fcall");
        let w_call = p.write(first, false, "/datum/q", "first", vec![Ref::Call(fcall)]);
        let w_plain = p.write(plain, false, "/datum/q", "plain", Vec::new());
        assert_eq!(p.order(), vec![w_call, w_plain]);
    }

    #[test]
    fn a_procedure_path_resolves_once_the_procedure_was_walked_and_not_for_itself() {
        let mut p = Program::new();
        p.procedure("/datum/q", "before");
        let f = p.procedure("/datum/q", "f");
        p.procedure("/datum/q", "after");
        let q = p.id("/datum/q");
        let (before, own, after) = (p.id("before"), p.id("f"), p.id("after"));
        let known = p.write(
            f,
            true,
            "/datum/q",
            "known",
            vec![Ref::Procedure {
                owner: q,
                name: before,
            }],
        );
        let itself = p.write(
            f,
            true,
            "/datum/q",
            "own",
            vec![Ref::Procedure {
                owner: q,
                name: own,
            }],
        );
        let later = p.write(
            f,
            true,
            "/datum/q",
            "later",
            vec![Ref::Procedure {
                owner: q,
                name: after,
            }],
        );
        // `known` resolves at once; the procedure itself and a later one wait for the second pass.
        assert_eq!(p.order(), vec![known, itself, later]);
    }

    #[test]
    fn a_type_resolves_once_its_subtree_was_walked() {
        let mut p = Program::new();
        let earlier = p.field("/datum/earlier", "x");
        let f = p.procedure("/datum/q", "f");
        p.field("/datum/later", "y");
        let (before, after) = (p.id("/datum/earlier"), p.id("/datum/later"));
        let known = p.write(f, true, "/datum/q", "known", vec![Ref::Type(before)]);
        let unknown = p.write(f, true, "/datum/q", "unknown", vec![Ref::Type(after)]);
        let plain = p.write(earlier, false, "/datum/earlier", "x", Vec::new());
        // The static that reads the later type waits for the second pass; the other two resolve in the first.
        assert_eq!(p.order(), vec![plain, known, unknown]);
    }
}
