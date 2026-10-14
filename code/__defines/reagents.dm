#define REAGENT_CONTAINER_CAN_BE_PLACED_INTO_DEFAULT "default_container"
#define REAGENT_CONTAINER_CAN_BE_PLACED_INTO_WATERCOOLER "watercooler_container"
#define REAGENT_CONTAINER_CAN_BE_PLACED_INTO_NONE "forbidden_container"

// The modes of a needle container (library/reagents/needle.dm): the value of the holder var its needle() names.
/// Taking reagents (or blood) in.
#define NEEDLE_DRAW 0
/// Putting reagents out (into a container or a person).
#define NEEDLE_INJECT 1
/// Broken by a stab: it does nothing more.
#define NEEDLE_BROKEN 2
/// Capped: it does nothing until it is used in hand.
#define NEEDLE_CAPPED 10
