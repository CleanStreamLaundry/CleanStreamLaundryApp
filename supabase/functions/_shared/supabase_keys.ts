// A configured name must resolve exactly; never select another key implicitly.
export function selectNamedSupabaseKey(
  name: string,
  serialized: string | undefined,
  kind: "secret" | "publishable",
): string | null {
  if (
    !name || name.trim() !== name ||
    [...name].some((char) =>
      char.charCodeAt(0) < 32 || char.charCodeAt(0) === 127
    )
  ) {
    return null;
  }
  try {
    const keys: unknown = JSON.parse(serialized ?? "");
    if (
      !keys || typeof keys !== "object" || Array.isArray(keys) ||
      !Object.hasOwn(keys, name)
    ) return null;
    const key = (keys as Record<string, unknown>)[name];
    return typeof key === "string" && key.trim() === key &&
        (kind === "secret"
          ? /^sb_secret_[A-Za-z0-9_-]+$/
          : /^sb_publishable_[A-Za-z0-9_-]+$/).test(key)
      ? key
      : null;
  } catch {
    return null;
  }
}

export function callerPublishableKey(
  env: (name: string) => string | undefined,
  selector: string,
): string {
  const name = env(selector);
  const key = name === undefined
    ? env("SUPABASE_ANON_KEY")
    : selectNamedSupabaseKey(
      name,
      env("SUPABASE_PUBLISHABLE_KEYS"),
      "publishable",
    );
  if (!key) throw new Error("Public key configuration unavailable");
  return key;
}
