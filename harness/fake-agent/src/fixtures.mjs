import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const fixtureDir = resolve(here, "../../protocol-fixtures");

export async function readFixture(name) {
  const raw = await readFile(resolve(fixtureDir, name), "utf8");
  return JSON.parse(raw);
}
