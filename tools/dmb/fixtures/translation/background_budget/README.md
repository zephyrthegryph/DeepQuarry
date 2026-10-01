# Background loop scheduling

BYOND stores the Background proc attribute and schedules budgeted F8/F9/FA transfers directly. Native code emits no explicit sleep for loop tails or authored continue. The OpenDream exporter previously inserted sleep(-1), introducing an additional yield and separating marked do/while conditions from their backedges. Its synthetic sleeps are removed; authored sleep remains.

Eight fresh native pairs cover while/do, authored continue, protected and nested loops, inherited overrides, ordinary foreground control and explicit sleep(-1). Complete bodies and explicit Sleep opcode counts pass in both debug modes. No runtime was executed.
