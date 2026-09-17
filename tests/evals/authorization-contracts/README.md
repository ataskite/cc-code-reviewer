# Authorization contract model evaluation

These Maven fixtures exercise the enterprise Security framework's semantic
authorization review. They are intentionally small and contain no attack
runner or production credentials. Run each project with the plugin in
`security` mode and the same model profile.

Both cases register a complete in-repo entry chain: the CLI entry
(`eval.Main`) reads the resource key from the command line, assembles the
store and sink, and invokes the flow with an authenticated subject. Entry
registration and assembly are therefore closed by repository evidence, so
the framework's production-reachability rule is satisfiable and the
vulnerable case is expected to be statically provable.

## Cases

- `horizontal-unbound`: the externally supplied resource key is resolved to
  a record owned by another subject and sent to a sensitive sink without
  any owner/tenant decision.
  Expected: one high-confidence horizontal authorization finding with
  evidence state `静态已证实`, containing the entry, subject, resource,
  missing decision, and sink evidence.
- `owner-bound`: the record owner is explicitly compared with the
  authenticated subject before the sink is reached, and an absent or
  mismatched record is denied. The control intentionally avoids a
  `findOwned(...)` method name so the evaluation checks semantic binding,
  not a helper-name heuristic.
  Expected: no horizontal authorization finding; the model may still report
  unrelated issues only if independently evidenced.
- `matrix-unbound`: one entry exposes four authorization failures through
  separate actions: another subject's object can be read, a mixed-tenant batch
  can be exported, a regular subject can invoke a privileged operation, and a
  client-controlled privileged property is applied. Expected: findings cover
  horizontal/object-level, cross-tenant batch, function-level, and
  property-level authorization with the relevant subject/action/resource/sink
  evidence.
- `matrix-bound`: the same four actions enforce owner and tenant binding for
  the single object, validate every item in the batch, require the privileged
  role, and allowlist the mutable property. Expected: no authorization
  finding; the model may still report unrelated issues only if independently
  evidenced.

Run each case five times. Each expected vulnerability class should be found at
least four times and each control should produce at most one false positive.
This is a model-quality target, not a deterministic test-suite assertion.
