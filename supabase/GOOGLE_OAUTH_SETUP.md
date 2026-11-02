# Google sign-in setup

The app calls Supabase Auth for Google OAuth. The Google OAuth client secret must stay in Supabase Auth settings and must never be placed in Flutter source, `.env` shipped with the app, or an Android/iOS resource.

## Supabase project

Project ref: `xfgayjbfhmoiqmrvbhje`

1. In Google Cloud Console, configure the OAuth consent screen and create a **Web application** OAuth client.
2. Add this authorized redirect URI in Google Cloud:
   `https://xfgayjbfhmoiqmrvbhje.supabase.co/auth/v1/callback`
3. In Supabase Dashboard → Authentication → Sign In / Providers → Google, enable the provider and enter that OAuth client ID and client secret.
4. In Supabase Dashboard → Authentication → URL Configuration, allow:
   `com.dueit.due_it://auth-callback`
5. Keep the provider scopes to `openid email profile`. DueIt only uses Google identity for sign-in; it does not request Gmail/mailbox access.

Google provider status was checked on 2026-11-02 and was disabled. The app code and native callback are ready, but Google sign-in cannot complete until the client credentials are added and the provider is enabled in the project.

## Session lifetime

Supabase Flutter session persistence and automatic access-token refresh are explicitly enabled in the app. Google OAuth creates a Supabase session; the app does not need or request a Google API refresh token.
