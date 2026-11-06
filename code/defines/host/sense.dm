// Sensing (code/domains/verdigris/sense.dm): ops of the batched vg_sense_commit() list. The numbers are verdigris/ffi/src/sense.rs's.
#define SENSE_OP_ADD 1
#define SENSE_OP_REMOVE 2
#define SENSE_OP_FORGET 3
// What a sensed() reads: a gas channel of a mixture (the default), or a SMES's stored charge.
#define SENSE_SOURCE_GAS 1
#define SENSE_SOURCE_CHARGE 2
