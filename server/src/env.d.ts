declare namespace Cloudflare {
  interface Env {
    DB: D1Database;
    CAP: string;
    MACS: string;
  }
}
type Env = Cloudflare.Env;
