declare namespace Cloudflare {
  interface Env {
    DB: D1Database;
    CAP: string;
    MACS: string;
    /** CLA-175: the Mac limit of a paid account. MACS stays the limit of a beta seat. */
    PAID_MACS: string;
    /** CLA-133: a 3rd Mac may replace the least used one SWAPS times in SWAP_DAYS days per account. */
    SWAPS: string;
    SWAP_DAYS: string;
    /** Link mails a day; Resend's free plan allows 100 for the whole account. */
    MAIL_DAY: string;
    /** Link mails per address and per device: an hour, and a day. */
    MAIL_HOUR: string;
    MAIL_DAY_EACH: string;
    /** CLA-172: waitlist tries a day from the beta page, all addresses together. */
    WAIT_DAY: string;
    /** CLA-172: "Email me the link" mails a day, all addresses together. */
    LINK_DAY: string;
    /** The Origin of the activation page; its path is /activate/. Default https://getmypod.app. */
    PAGE_ORIGIN?: string;
    /** Worker secrets that Jason adds. Never in the repo. */
    TURNSTILE_SECRET?: string;
    RESEND_KEY?: string;
    /** CLA-175: Stripe's restricted key (Checkout sessions: write and read). A Worker secret. */
    STRIPE_KEY?: string;
    /** CLA-175: the Stripe price ID of myPod. A plain setting. None: Buy answers "sales". */
    STRIPE_PRICE?: string;
    /** CLA-175: the signing secret of Stripe's webhook (whsec_...). A Worker secret. */
    STRIPE_WEBHOOK_SECRET?: string;
    /** CLA-175: "thank you" page checks an hour per network. */
    BOUGHT_HOUR: string;
    /** CLA-175: Buy presses (new payment pages) an hour per network. */
    BUY_HOUR: string;
    /** CLA-175: the stop-sales switch. Only "1" makes new payment pages; anything else: Buy answers "sales". */
    SALES?: string;
    ALERT_TO?: string;
    /** CLA-172: "1" only on the test server (wrangler env "test"): noindex on every answer. */
    TEST_SERVER?: string;
    /** CLA-172: the host the test Turnstile key answers with. Read only when TEST_SERVER is "1". */
    TURNSTILE_HOST?: string;
    /** CLA-172: the test server's stand-in beta build when there is no feed. Read only when TEST_SERVER is "1". */
    TEST_BUILD?: string;
    /** CLA-175: "1" serves the launch page at "/" (the test server only, until Jason says go live). */
    LAUNCH_PAGE?: string;
    /** The static files. The test server runs the Worker first for every path; live only for "/". */
    ASSETS?: Fetcher;
  }
}
type Env = Cloudflare.Env;
