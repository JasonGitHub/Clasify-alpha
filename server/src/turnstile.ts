/**
 * Cloudflare Turnstile's server check for the page's bot token. True only when Cloudflare says
 * success for our own page (the hostname of PAGE_ORIGIN). No IP is sent (remoteip is optional). A timeout or an error is false.
 */
export function turnstile(secret: string | undefined, hostname: string, fetcher: typeof fetch = fetch) {
  return async (token: string): Promise<boolean> => {
    if (!secret || !token || token.length > 2048) return false;  // no secret yet: fail closed
    const response = await fetcher("https://challenges.cloudflare.com/turnstile/v0/siteverify", {
      method: "POST",
      body: new URLSearchParams({ secret, response: token }),
      signal: AbortSignal.timeout(5_000),
    }).catch(() => null);
    const answer = response?.ok ? await response.json().catch(() => null) as { success?: boolean; hostname?: string } | null : null;
    return answer?.success === true && answer.hostname === hostname;
  };
}
