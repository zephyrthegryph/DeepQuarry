// The conditions a question re-checks when its answer arrives (code/library/prompts/answer_checks.dm: answerer_holds()).

#define ANSWER_ALIVE (1<<0)
#define ANSWER_CONSCIOUS (1<<1)
#define ANSWER_CAPABLE (1<<2)
#define ANSWER_UNRESTRAINED (1<<3)
#define ANSWER_ADJACENT (1<<4)
#define ANSWER_NEAR_SUBJECT (1<<5)
#define ANSWER_HELD (1<<6)
#define ANSWER_CARRIED (1<<7)
/// The common "someone offers you something" set: both awake and next to each other.
#define ANSWER_FACE_TO_FACE (ANSWER_CONSCIOUS | ANSWER_ADJACENT)
