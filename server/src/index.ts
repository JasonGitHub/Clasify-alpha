import { handle } from "./activation";
import { noMail } from "./mailer";

export default {
  fetch: (request, env) => handle(request, env, { now: Date.now, mailer: noMail }),
} satisfies ExportedHandler<Env>;
