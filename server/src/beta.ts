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

/** `testBuild`: the test server's stand-in build, used only when the feed has none (see testBuild()). */
export async function beta(db: D1Database, cap: number, fetcher: typeof fetch, now: number, testBuild: number | null = null): Promise<Beta> {
  if (kept && kept.cap === cap && now >= kept.at && now - kept.at < keepFor) return kept.answer;
  const taken = (await db.prepare("SELECT COUNT(*) AS n FROM accounts WHERE state = 'active'").first<{ n: number }>())?.n ?? 0;
  let newest = await latest(fetcher);
  if (newest.build === null && testBuild !== null) {
    newest = { build: testBuild, url: downloadURL(`https://${downloadHost}/beta/myPod-beta-${testBuild}.dmg`) };
  }
  const answer = { taken, cap, full: taken >= cap, ...newest };
  kept = { at: now, cap, answer };
  return answer;
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

/** The newest beta's build and link. No file, a slow answer (5 s) or a bad file: both null. */
async function latest(fetcher: typeof fetch): Promise<{ build: number | null; url: string | null }> {
  const none = { build: null, url: null };
  const response = await fetcher(latestURL, { signal: AbortSignal.timeout(5_000) }).catch(() => null);
  if (!response?.ok) return none;
  const feed = await response.json().catch(() => null) as { build?: unknown; url?: unknown } | null;
  const url = downloadURL(feed?.url);
  const build = feed?.build;
  if (!url || typeof build !== "number" || !Number.isSafeInteger(build) || build < 1) return none;
  return { build, url };
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
