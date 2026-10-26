import { KisiClient, KisiError } from "../../supabase/functions/_shared/kisi.ts";
import { startKisiSandbox } from "./sandbox.ts";

const sandbox = await startKisiSandbox(0);
try {
  const client = new KisiClient({ environment: "local-sandbox", port: sandbox.port });
  console.log("Kisi LOCAL SIMULATION — no physical doors, account, or credentials used.");
  const { items: places } = await client.listPlaces();
  const { items: doors } = await client.listLocks(places[0].id);
  for (const door of doors) {
    try {
      const result = await client.unlock(door.id);
      console.log(`${door.name}: ${result.outcome} (simulated)`);
    } catch (error) {
      if (!(error instanceof KisiError)) throw error;
      console.log(`${door.name}: ${error.kind}${error.providerCode ? ` [${error.providerCode}]` : ""}`);
    }
  }
} finally { await sandbox.close(); }
