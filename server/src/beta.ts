// CLA-172: the beta page's numbers (GET /v1/beta). A count only, never who. The page never
// reads dl.getmypod.app itself: the Worker reads the beta feed and passes on a checked link.

/** The beta feed that app-dmg.yml writes: { build, date, file, url }. */
export const latestURL = "https://dl.getmypod.app/beta/latest.json";
/** The only host a download link may point to (the same rule as BetaDownload.url in the app). */
export const downloadHost = "dl.getmypod.app";

export interface Beta { taken: number; cap: number; full: boolean; build: number | null; url: string | null }

/** How long an isolate keeps the answer, so a burst of visitors costs one read per isolate. */
export const keepFor = 30_000;
let kept: { at: number; cap: number; answer: Beta } | null = null;

/** How old the kept feed may be before a visit refreshes it in the background. A new build then
 * shows within about 3 minutes of its upload (this, the 30 s keep here and the page's 30 s). */
export const feedFresh = 120_000;

type Newest = { build: number | null; url: string | null };

/**
 * The count and the newest beta, from one D1 batch: the page path never waits for the feed.
 * `testBuild`: the test server's stand-in build, used only when the feed has none (see testBuild()).
 * `later`: runs the background refresh after the answer (the Worker's waitUntil).
 */
export async function beta(db: D1Database, cap: number, fetcher: typeof fetch, now: number, testBuild: number | null = null,
  later: (work: Promise<unknown>) => void = (work) => { work.catch(() => null); }): Promise<Beta> {
  if (kept && kept.cap === cap && now >= kept.at && now - kept.at < keepFor) return kept.answer;
  const [count, feed] = await db.batch<Record<string, unknown>>([
    db.prepare("SELECT COUNT(*) AS n FROM accounts WHERE state = 'active'"),
    db.prepare("SELECT build, url, checked_at FROM beta_feed WHERE id = 1"),
  ]);
  const taken = Number(count.results[0]?.n ?? 0);
  const row = feed.results[0] as { build: unknown; url: unknown; checked_at: number } | undefined;
  let newest: Newest;
  if (!row) newest = await refreshFeed(db, fetcher, now);  // only the very first time: nothing kept yet
  else {
    newest = checked(row);
    if (now - row.checked_at >= feedFresh || now < row.checked_at) later(refreshFeed(db, fetcher, now));
  }
  if (newest.build === null && testBuild !== null) {
    newest = { build: testBuild, url: downloadURL(`https://${downloadHost}/beta/myPod-beta-${testBuild}.dmg`) };
  }
  const answer = { taken, cap, full: taken >= cap, ...newest };
  kept = { at: now, cap, answer };
  return answer;
}

/**
 * Reads the feed and keeps it in D1. No file or a bad file: no build. No answer (an error, 5xx,
 * 5 s): the last kept build stays, so a short outage hides nothing; only the check time moves on.
 */
export async function refreshFeed(db: D1Database, fetcher: typeof fetch, now: number): Promise<Newest> {
  const got = await latest(fetcher);
  if (got === "unknown") {
    const row = await db.prepare("INSERT INTO beta_feed (id, build, url, checked_at) VALUES (1, NULL, NULL, ?) "
      + "ON CONFLICT(id) DO UPDATE SET checked_at = excluded.checked_at RETURNING build, url").bind(now).first<{ build: unknown; url: unknown }>();
    return row ? checked(row) : { build: null, url: null };
  }
  await db.prepare("INSERT INTO beta_feed (id, build, url, checked_at) VALUES (1, ?, ?, ?) "
    + "ON CONFLICT(id) DO UPDATE SET build = excluded.build, url = excluded.url, checked_at = excluded.checked_at")
    .bind(got.build, got.url, now).run();
  return got;
}

/** A kept row, checked again by the same rules as the feed: both, or neither. */
function checked(row: { build: unknown; url: unknown }): Newest {
  const url = downloadURL(row.url);
  const build = row.build;
  if (!url || typeof build !== "number" || !Number.isSafeInteger(build) || build < 1) return { build: null, url: null };
  return { build, url };
}

/**
 * CLA-172: the test server has no public beta feed, so TEST_BUILD names a stand-in build. The
 * page then shows its download states; the link names a file that does not exist. Only with
 * TEST_SERVER "1", and only a whole number from 1: the live Worker never reads it.
 */
export function testBuild(env: Env): number | null {
  if (env.TEST_SERVER !== "1" || !env.TEST_BUILD || !/^[1-9][0-9]{0,8}$/.test(env.TEST_BUILD)) return null;
  return Number(env.TEST_BUILD);
}

/** For tests: the next call reads again. */
export function forgetBeta() { kept = null; }

/** The feed's build and link. No file or a bad file: both null. No answer (an error, 5xx, 5 s): "unknown". */
async function latest(fetcher: typeof fetch): Promise<Newest | "unknown"> {
  const none = { build: null, url: null };
  const response = await fetcher(latestURL, { signal: AbortSignal.timeout(5_000) }).catch(() => null);
  if (!response || response.status >= 500) return "unknown";
  if (!response.ok) return none;
  const feed = await response.json().catch(() => null) as { build?: unknown; url?: unknown } | null;
  return checked({ build: feed?.build, url: feed?.url });
}

/** Only an https link to exactly dl.getmypod.app, with no user, password or port and a file path. */
export function downloadURL(value: unknown): string | null {
  if (typeof value !== "string") return null;
  let url: URL;
  try { url = new URL(value); } catch { return null; }
  if (url.protocol !== "https:" || url.hostname !== downloadHost || url.username || url.password || url.port) return null;
  if (url.pathname.length < 2 || url.search || url.hash) return null;
  return url.href;
}
