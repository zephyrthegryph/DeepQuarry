# Residual object effects: source-only review

Five production files, five overrides and twelve retained baseline fingerprints are addressed: material trash (5), fitted chewables (1), junkmail (1), communicator camera HUDs (2 plus 2 auxiliary list rows), implant chair (1).

Global source searches find no descendant Initialize overrides for these five families. Scrap setup retains original prob/rand and material additions after the unchanged mapload-sensitive trash parent. Fitted chewables use the existing make_exact_fit, which explicitly materializes latent starting contents; no storage lifecycle model is changed. Junkmail uses its existing one-shot content/name procedure. The camera uses its existing two unique HUD inclusions and does not change either global HUD. The implant chair uses a factory on its already-declared owns_many slot; its delete policy is unchanged, and the factory creates the same count of actual loyalty implants in the chair.

New focused tests assert bounded guaranteed scrap material, fitted contents/space, actual junkmail contents/name, exact camera HUD membership and existing implant ownership/deletion. No generation, compilation or tests have run. Root must wire dq_init_objects_residual_effects_tests.dm.

This patch is disjoint from remaining-nine.review.patch, remaining-material.review.patch and base-item-tool-intern.review.patch; any apply order is valid.
