use vg_core::law::{Law, LawCtx, LawKey, Period, Settle};
use vg_core::sim::{PacedDriver, SimBuilder, SimConfig};
use vg_core::units::Seconds;

struct First;
impl Law for First {
    type Reads = u32;
    type Writes = u32;
    const NAME: &'static str = "first";
    fn step(ctx: &mut LawCtx<'_, u32, u32>, _dt: Seconds) -> Settle {
        *ctx.writes = *ctx.reads + 1;
        ctx.emit(*ctx.writes);
        Settle::Sleep
    }
}

struct Second;
impl Law for Second {
    type Reads = u32;
    type Writes = u64;
    const NAME: &'static str = "second";
    const PERIOD: Period = Period::Ticks(2);
    fn step(ctx: &mut LawCtx<'_, u32, u64>, dt: Seconds) -> Settle {
        *ctx.writes = u64::from(*ctx.reads);
        ctx.emit(*ctx.reads);
        assert_eq!(dt, Seconds(0.5));
        Settle::Active
    }
}

#[test]
fn ordered_laws_execute_in_one_sim_and_sleep_until_woken() {
    let mut builder = SimBuilder::new(SimConfig::default());
    let input = builder.add_resource("input", 3u32);
    let middle = builder.add_resource("middle", 0u32);
    let output = builder.add_resource("output", 0u64);
    // Register in reverse order. An explicit edge establishes execution.
    let second = builder.add_law::<Second>(middle, output, Seconds(0.25));
    let first = builder.add_law::<First>(input, middle, Seconds(0.25));
    builder.law_after::<Second, First>();
    let mut sim = builder.build().unwrap();
    sim.begin_tick();
    assert!(sim.dispatch_frame());
    sim.wait_for_frame();
    assert_eq!(sim.drain_law(first), Some((vec![4], vec![])));
    assert_eq!(sim.drain_law(second), Some((vec![4], vec![])));
    assert_eq!(sim.law_active(first), Some(false));
    sim.begin_tick();
    assert!(sim.dispatch_frame());
    sim.wait_for_frame();
    assert_eq!(sim.drain_law(first), Some((vec![], vec![])));
    sim.wake_law(first);
    sim.begin_tick();
    assert!(sim.dispatch_frame());
    sim.wait_for_frame();
    assert_eq!(sim.drain_law(first), Some((vec![4], vec![])));
}

#[test]
fn paced_driver_keeps_due_step_when_frame_is_busy() {
    let sim = SimBuilder::new(SimConfig::default()).build().unwrap();
    let mut sim = sim;
    let mut driver = PacedDriver::new(Seconds(0.25), 3);
    driver.advance(Seconds(0.75));
    assert_eq!(driver.due(), 3);
    sim.begin_tick();
    assert!(driver.dispatch(&mut sim));
    assert_eq!(driver.due(), 2);
    sim.wait_for_frame();
    sim.begin_tick();
    assert!(driver.dispatch(&mut sim));
    sim.wait_for_frame();
    sim.begin_tick();
    assert!(driver.dispatch(&mut sim));
    assert_eq!(driver.due(), 0);
}

#[test]
fn law_order_cycle_rejects_build() {
    let mut builder = SimBuilder::new(SimConfig::default());
    let a = builder.add_resource("a", 1u32);
    let b = builder.add_resource("b", 2u32);
    let c = builder.add_resource("c", 3u64);
    let _: LawKey<First> = builder.add_law(a, b, Seconds(1.0));
    let _: LawKey<Second> = builder.add_law(b, c, Seconds(1.0));
    builder
        .law_after::<First, Second>()
        .law_after::<Second, First>();
    assert!(builder.build().is_err());
}
