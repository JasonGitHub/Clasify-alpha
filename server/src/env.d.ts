declare namespace Cloudflare {
  interface Env {
    DB: D1Database;
    CAP: string;
    MACS: string;
    /** Link mails a day; Resend's free plan allows 100 for the whole account. */
    MAIL_DAY: string;
    /** Link mails per address and per device: an hour, and a day. */
    MAIL_HOUR: string;
    MAIL_DAY_EACH: string;
    /** Worker secrets that Jason adds. Never in the repo. */
    TURNSTILE_SECRET?: string;
    RESEND_KEY?: string;
    ALERT_TO?: string;
  }
}
type Env = Cloudflare.Env;
