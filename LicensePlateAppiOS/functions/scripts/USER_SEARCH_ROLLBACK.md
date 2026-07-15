# User Search Rollback Notes

## If `searchUsers` must be rolled back

1. Redeploy the previous Cloud Functions revision (without `searchUsers` / index triggers).
2. Old app builds that still call `searchUsers` will fail closed until users update, or temporarily keep the callable as a no-op returning `{ results: [] }`.
3. Client legacy helpers (`searchByEmail` / `searchByPhone` / `searchByUsernameContains`) remain in `UserRepository.swift` but are unused. Re-wire `searchUsers` to them only as a last resort — they leak email/phone on readable docs and lack normalization.

## If public PII strip must be reversed

1. Do **not** re-copy from Auth alone if `users/{uid}/private/contact` exists — that is the source of truth after backfill.
2. Restore with Admin SDK:
   - Read `private/contact` → set `email` / `phoneNumber` on public `users/{uid}`.
3. Re-run `DRY_RUN=1 npm run backfill:user-search` then live backfill without `STRIP_PUBLIC_PII` if indexes were wiped.

## Index rebuild

```bash
cd functions
DRY_RUN=1 npm run backfill:user-search
npm run backfill:user-search
# After clients ship private/contact-only writes:
STRIP_PUBLIC_PII=1 npm run backfill:user-search
```

## Anonymous discoverability

Triggers delete lookup docs when `isRegistered === false`. Callable also drops those hits after loading the user doc. Invite callables still reject unregistered recipients.
