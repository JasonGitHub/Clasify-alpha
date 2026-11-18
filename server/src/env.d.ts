declare namespace Cloudflare {
  interface Env {
    DB: D1Database;
    CAP: string;
    MACS: string;
    /** Link mails a day; Resend's free plan allows 100 for the whole account. */
    MAIL_DAY: string;
    /** Worker secrets that Jason adds. Never in the repo. */
    RESEND_KEY?: string;
    ALERT_TO?: string;
  }
}
type Env = Cloudflare.Env;
