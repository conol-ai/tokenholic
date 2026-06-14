# Supabase sync setup

Tokenholic syncs a small per-device summary through your own Supabase project so
every device shows one combined total. Auth is Google / GitHub. ~10 minutes.

> The anon key you'll paste into the app is **public and safe to ship** — Row-Level
> Security guarantees each signed-in user can only read/write their own device
> rows. Never put the `service_role` key in the app.

## 1. Create the project

1. Create a free project at [supabase.com](https://supabase.com).
2. **Settings → API**: copy the **Project URL** (`https://<ref>.supabase.co`) and
   the **anon / public** key.

## 2. Create the table

**SQL Editor** → paste and run [`supabase/schema.sql`](supabase/schema.sql). It
creates `device_snapshots` with RLS policies, an `updated_at` trigger, and the
Realtime publication.

## 3. Allow the app's redirect

**Authentication → URL Configuration → Redirect URLs** → add exactly (lowercase):

```
ai.conol.tokenholic://auth-callback
```

This is the **only** place the custom scheme is registered with Supabase.

## 4. Enable the providers

The provider redirect URI is always the **Supabase** callback
`https://<ref>.supabase.co/auth/v1/callback` — never the app's custom scheme.

### Google
1. Google Cloud Console → **APIs & Services → Credentials → Create OAuth client ID**.
2. Application type **Web application** (not Desktop/iOS — Supabase does the
   server-side exchange).
3. **Authorized redirect URI** = `https://<ref>.supabase.co/auth/v1/callback`.
4. Copy the Client ID + Client Secret into **Supabase → Authentication →
   Providers → Google**, enable it.

### GitHub
1. GitHub → **Settings → Developer settings → OAuth Apps → New OAuth App**.
2. **Authorization callback URL** = `https://<ref>.supabase.co/auth/v1/callback`.
3. Copy Client ID + Client Secret into **Supabase → Providers → GitHub**, enable it.

## 5. Point the app at your project

Edit `Sources/Tokenholic/Sync/SupabaseConfig.swift`:

```swift
static let projectURL = "https://<ref>.supabase.co"
static let anonKey    = "<your anon/public key>"
```

Rebuild (`make`). Until these are real values, sync is disabled and Tokenholic
runs local-only.

## 6. Test

Run Tokenholic on two devices, sign in with the same account on both, and confirm
each device's row appears and the combined total adds up (with the subscription
subtracted once).

---

**Apple Sign In** is not wired yet: the native flow needs a Developer ID + the
`applesignin` entitlement (ad-hoc signing can't carry it). It can be added via a
Services-ID web flow, or once the app moves to Developer ID signing.
