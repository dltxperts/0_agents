# Rust conventions

## Verification (every change)

```
cargo fmt --all --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
```

`-D warnings` is mandatory — clippy warnings are errors. For non-workspace
crates, drop the `--workspace` / `--all` flags accordingly.

## Error handling

- Use `thiserror` for typed domain errors. No raw string errors crossing
  module boundaries.
- Domain layers expose typed errors. The API/transport layer translates them
  to HTTP responses or RPC errors. **Never leak raw DB errors** (sqlx, diesel,
  etc.) to callers.
- `anyhow` is acceptable for binary entry points and orchestration glue, not
  for library APIs.

## Determinism (when ordering or repeatability matters)

For canonicalization, merge logic, hashing, or any code path whose output must
be reproducible:

- Use `BTreeMap` / `IndexMap` instead of `HashMap` when iteration order
  matters. `HashMap` iteration order is non-deterministic.
- Use stable sort with explicit tie-breakers. No random tie-breakers.
- Avoid relying on `HashSet` ordering.
- Same inputs must always produce the same output.

For non-deterministic code (UI state, user-driven flows), `HashMap` is fine.

## Async

- Runtime: tokio. Single global runtime, default work-stealing scheduler.
- Don't call `block_on` inside async contexts — it deadlocks the runtime.
  For sync APIs that must be invoked from async code, use
  `tokio::task::spawn_blocking`. For CPU-bound work, also `spawn_blocking`.
- Prefer `async fn` in trait definitions when the language version permits.
- Bounded channels (`tokio::sync::mpsc::channel(N)`) over unbounded — they
  apply backpressure naturally and surface saturation as errors instead of
  unbounded memory growth.

## Code style

- Public types in library crates should have doc comments describing
  invariants and intended use. Use `///` above the type, not block comments.
- Prefer constructors that validate invariants over public field mutation.
- Match exhaustively. Avoid `_ =>` arms unless the type is genuinely open
  (e.g. an external enum or a `#[non_exhaustive]` upstream type).

## Tooling

- `cargo fmt` on save (editor config).
- `cargo clippy -- -D warnings` enforced in CI.
- `cargo-nextest` for fast test runs when the project supports it.
