#define I_SINGULO "singulo"
#define EMITTER_DAMAGE_POWER_TRANSFER 450 //used to transfer power to containment field generators
/// The singularity's step interval: it eats, dissipates and grows or shrinks every 2 s.
#define SINGULARITY_STEP_INTERVAL (2 SECONDS)
/// The rungs of floor_weld() (code/library/machine/floor_weld.dm): the machine core's `state` of a heavy machine bolted and welded to the floor.
#define FLOOR_WELD_LOOSE 0
#define FLOOR_WELD_BOLTED 1
#define FLOOR_WELD_WELDED 2
#define MAXIMUM_TESLA_JUMPS 20
/// The gravity generator's spin (its charging_state): settled, spinning up, spinning down.
#define GRAVGEN_IDLE 0
#define GRAVGEN_UP 1
#define GRAVGEN_DOWN 2
