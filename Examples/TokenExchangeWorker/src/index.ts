interface Env {
  GITHUB_CLIENT_ID: string;
  GITHUB_CLIENT_CREDENTIAL: string;
  ALLOWED_REDIRECT_URI: string;
}

interface ExchangeRequest {
  code: string;
  redirectURI: string;
  codeVerifier: string;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method !== "POST") return new Response("Method Not Allowed", { status: 405 });

    const body = await request.json<ExchangeRequest>();
    if (!body.code || !body.codeVerifier || body.redirectURI !== env.ALLOWED_REDIRECT_URI) {
      return Response.json({ error: "invalid_request" }, { status: 400 });
    }

    const response = await fetch("https://github.com/login/oauth/access_token", {
      method: "POST",
      headers: { "Accept": "application/json", "Content-Type": "application/json", "User-Agent": "GitHubSyncKit-TokenExchange" },
      body: JSON.stringify({
        client_id: env.GITHUB_CLIENT_ID,
        client_secret: env.GITHUB_CLIENT_CREDENTIAL,
        code: body.code,
        redirect_uri: body.redirectURI,
        code_verifier: body.codeVerifier
      })
    });

    const result = await response.json<{ access_token?: string; error?: string; error_description?: string }>();
    if (!response.ok || !result.access_token) {
      return Response.json({ error: result.error ?? "exchange_failed", message: result.error_description }, { status: 401 });
    }

    return Response.json({ accessToken: result.access_token }, { headers: { "Cache-Control": "no-store" } });
  }
};
