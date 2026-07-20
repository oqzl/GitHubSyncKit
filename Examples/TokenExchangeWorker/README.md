# TokenExchangeWorker

Minimal Cloudflare Worker for GitHub OAuth App Web Flow token exchange.

1. Set `GITHUB_CLIENT_ID` and `ALLOWED_REDIRECT_URI` in `wrangler.jsonc`.
2. Store the secret with `npx wrangler secret put GITHUB_CLIENT_SECRET`.
3. Deploy with `npm run deploy`.
4. Pass the deployed HTTPS endpoint to `BackendOAuthTokenExchanger`.

For production, add App Attest or another client-attestation mechanism, rate limiting, structured audit logs without secrets, and stricter origin/device validation. Never log the authorization code, code verifier, client secret, or access token.
