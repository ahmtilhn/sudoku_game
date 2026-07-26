# App Check Custom Backend

Sudoku Duel sends Firebase App Check tokens to the Worker in the
`X-Firebase-AppCheck` header for REST and WebSocket room connections.

The Worker verifier checks:

- token exists when `REQUIRE_APP_CHECK=true`
- JWT header algorithm is `RS256`
- JWT type is `JWT` when present
- issuer is `https://firebaseappcheck.googleapis.com/{FIREBASE_PROJECT_NUMBER}`
- audience contains `projects/{FIREBASE_PROJECT_NUMBER}`
- subject matches `ALLOWED_APP_CHECK_APP_IDS`
- token is not expired
- public keys come from `https://firebaseappcheck.googleapis.com/v1/jwks`

`REQUIRE_APP_CHECK=false` is the staging default. Missing tokens are allowed,
and invalid optional tokens are rejected internally without logging token
contents. `REQUIRE_APP_CHECK=true` makes private REST endpoints and WebSocket
room connection return `403`.

Required vars:

- `FIREBASE_PROJECT_NUMBER`
- `ALLOWED_APP_CHECK_APP_IDS`
- `REQUIRE_APP_CHECK`

Do not put App Check tokens in URLs, query strings, logs, or committed files.

Reference: Firebase documents custom backend protection as requiring the client
to send an App Check token and the backend to verify it before accepting
protected requests.

