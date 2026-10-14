# Google login and linked accounts

Google and Lichess can both authenticate the same internal User. Start with either
provider, then open **Account → Linked accounts** from the header's account menu and
connect the other one. The fresh provider flow links to the current library. Logging in
normally with a different, unlinked identity instead opens that identity's separate account.
Already-owned identities are rejected when linking; there is no automatic merge,
email matching or unlinking. The linked-accounts modal offers permanent self-service
deletion: it removes the account, its linked identities, every session and the
personal library links, while room content and underlying analyses remain.
Deleting a duplicate account frees its provider identity for linking to
another account. There is no account recovery.

## Google configuration

Create a **Web application** OAuth client in Google Cloud / Google Auth Platform.
Configure the consent application's branding/audience and any test users needed
for your chosen publishing status. Register this exact authorized redirect URI:

```text
https://openchesslab.com/auth/google/callback
```

Supply these runtime settings through the environment's secret manager:

```text
GOOGLE_CLIENT_ID=<web application's client ID>
GOOGLE_CLIENT_SECRET=<web application's client secret>
GOOGLE_REDIRECT_URI=https://openchesslab.com/auth/google/callback
```

Keep the existing `ACCOUNT_SUBJECT_HMAC_KEY` unchanged. Both providers use it;
replacing it would prevent resolution of existing accounts. Google is hidden
when all three Google settings are absent. Partial settings fail startup with a
sanitized error. Production requires HTTPS and the stable HMAC key. Development
may register `http://localhost:4000/auth/google/callback` on a separate test client.
Never commit client credentials or paste them into chat.

Production configuration and deployment are manual and require user direction.
No production settings were changed by the implementation. The normal release
migration renames `lichess_oauth_attempts` to `oauth_attempts`; pending five-minute
handshakes from the previous version must be restarted. Existing sessions and
account identities remain intact.

## Verification after configuration/deployment

1. Log in with Google in a fresh browser: the home page opens; the header account
   menu's My library and Linked accounts modals open over it and show Google
   connected and Lichess unconnected.
2. Connect Lichess from that modal. Log out and log in with either provider; the
   same saved analyses are visible in the library modal.
3. Also test connecting Google from an existing Lichess account.
4. Cancel a provider flow and check that the current login/library is preserved.
5. Try an identity already belonging to another internal account: it must report
   a conflict and preserve both accounts/libraries.
6. Delete a throwaway account after typing the confirmation word: every browser
   signs out, and that freed provider identity can then be linked to another
   account. Underlying analyses and room content must remain.

Provider HTTP responses are fixtures in automated tests; real Google consent
and browser callback behavior still need this manual verification.

## Privacy and authorization boundary

Only `openid` is requested, with state, S256 PKCE, nonce and the confidential
client secret. Email/profile scopes and offline access are not requested.
The direct TLS-verified token response authenticates the ID token's origin per
Google's server-flow documentation; no browser-supplied ID token is accepted.
Issuer, audience, authorized party, expiry, issued-at and nonce are checked.
Only the HMAC of Google's stable `sub` enters the existing Accounts storage.
Tokens and additional claims are discarded; Google consent itself is not revoked
on every login. There is no stored Google API grant.

An account link requires the same live browser credential at initiation and
callback, and it is checked again after provider verification under a database
row lock. A failed link never becomes a login or transfers another account.
Successful login/linking rotates the browser credential. Neither Google login
nor a Lichess identity link grants access to private Lichess data: games/studies
import and the necessary authorization/token lifecycle are still future work.

Official references checked 2026-10-14:
[Google OpenID Connect server flow](https://developers.google.com/identity/openid-connect/openid-connect),
[web-server OAuth client setup](https://developers.google.com/identity/protocols/oauth2/web-server).
