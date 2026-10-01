# Empty constant-true loops

Native while(1) and do{}while(1) compile to F8 targeting itself, followed by unreachable End. Their optimized OpenDream Jump has equal source/target byte addresses. Ordinary backward-or-equal transfers must perform the native loop budget operation; comparing only strictly backward addresses emitted an unbudgeted infinite jump. The paired test checks complete bodies and follows debug markers to confirm the self-backedge selects the same budgeted instruction.

Both complete native bodies and self-backedge controls pass in both debug modes.
