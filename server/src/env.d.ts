declare namespace Cloudflare {
  interface Env {
    DB: D1Database;
    CAP: string;
    MACS: string;
    /** CLA-133: a 3rd Mac may replace the least used one SWAPS times in SWAP_DAYS days per account. */
    SWAPS: string;
    SWAP_DAYS: string;
    /** Link mails a day; Resend's free plan allows 100 for the whole account. */
    MAIL_DAY: string;
    /** Link mails per address and per device: an hour, and a day. */
    MAIL_HOUR: string;
    MAIL_DAY_EACH: string;
    /** The Origin of the activation page; its path is /activate/. Default https://getmypod.app. */
    PAGE_ORIGIN?: string;
    /** Worker secrets that Jason adds. Never in the repo. */
    TURNSTILE_SECRET?: string;
    RESEND_KEY?: string;
    ALERT_TO?: string;
    /** CLA-172: "1" only on the test server (wrangler env "test"): noindex on every answer. */
    TEST_SERVER?: string;
    /** CLA-172: the host the test Turnstile key answers with. Read only when TEST_SERVER is "1". */
    TURNSTILE_HOST?: string;
    /** The static files; bound only on the test server, which runs the Worker first. */
    ASSETS?: Fetcher;
  }
}
type Env = Cloudflare.Env;
