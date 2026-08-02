# Post-mortem template (architect, on exhaustion — R13)

Write `runs/<run-id>/post-mortem.md` with exactly these sections:

## What failed

Which gates were still failing at exhaustion, with the final failing output (trimmed to the diagnostic core).

## Why the builder appears stuck

Your diagnosis from the iteration history (`runs/<run-id>/iterations/*.json`): misread requirement, oscillation between two fixes, capability gap, environment issue, or a gate the task text doesn't justify (if so, say why the gate survived re-diagnosis).

## Suggested next step

One concrete recommendation: a sharper task statement, a different builder, a human fix on the branch (`fusion/<run-id>` holds the best attempt), or task decomposition.
