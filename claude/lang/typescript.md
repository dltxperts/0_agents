# TypeScript conventions

Package manager preference: **bun** for new projects; respect what the project
already uses (npm / pnpm / yarn).

## Type safety (mandatory)

- **No `any`. Ever.** No `as any`, `Array<any>`, `Record<string, any>`. Use
  `unknown` + narrowing, generics, discriminated unions, or `JsonValue`
  (defined below).
- **Explicit return types on all exported functions.** Inferred return types
  are fine for local helpers.
- **No unsafe TS escapes.** No `@ts-ignore`, `@ts-nocheck`. Non-null `!` is
  allowed only for React refs after a guard.
- **Exhaustive union switches** using an `assertNever(value: never)` helper.
- **`catch` is always `unknown`** — narrow before using.

### Required tsconfig

```json
{
  "compilerOptions": {
    "strict": true,
    "noImplicitAny": true,
    "useUnknownInCatchVariables": true,
    "noUncheckedIndexedAccess": true,
    "exactOptionalPropertyTypes": true,
    "noImplicitReturns": true,
    "noFallthroughCasesInSwitch": true
  }
}
```

## Code style

- `function` declarations for top-level exports, arrow functions for callbacks
  only.
- `type` for unions, intersections, branded IDs. `interface` for extendable
  object shapes.
- **No `enum`** — use string unions instead. Enums have several footguns
  (numeric reverse-mapping, runtime cost) that string unions avoid.
- **Named exports only.** No default exports. Exception: framework-required
  defaults (Next.js page files, etc.).
- ES modules only. Never `require()`.
- `import type` for type-only imports.
- Import order: built-in → external → internal → parent / sibling → type
  imports.

## Useful patterns

### Branded IDs

```ts
type Brand<T, B extends string> = T & { readonly __brand: B };
type UserId = Brand<string, "UserId">;
type OrderId = Brand<string, "OrderId">;
```

Prevents accidentally passing a `UserId` where an `OrderId` is expected.

### JsonValue

```ts
type JsonValue =
  | null
  | boolean
  | number
  | string
  | JsonValue[]
  | { readonly [k: string]: JsonValue };
```

Use as the type for unknown JSON payloads instead of `any` or bare `unknown`.

## React-specific

- One component per file. Only other allowed export is the props interface.
- No helper functions in component files — extract to `helpers.ts` or a hook.
- Components are thin orchestrators: compose hooks, wire outputs to JSX.

## Verification

```
bun run typecheck    # or: tsc --noEmit
bun run lint         # eslint
bun run test
```

App-visible frontend changes need a real browser check (Playwright or manual
UI verification). Typecheck / build / unit tests are supporting checks only —
they do NOT prove UI correctness.
