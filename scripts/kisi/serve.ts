import { startKisiSandbox } from "./sandbox.ts";

const sandbox = await startKisiSandbox();
console.log(`Kisi LOCAL SIMULATION at http://127.0.0.1:${sandbox.port}`);
console.log("Synthetic credential: cleanstream-local-kisi-only. No hardware or external account is used.");
for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.once(signal, async () => { await sandbox.close(); });
}
