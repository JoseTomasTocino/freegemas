import fs from "node:fs";
import path from "node:path";

const [input, output, symbol] = process.argv.slice(2);
if (!input || !output || !symbol) throw new Error("bin2c input output symbol");
const bytes = fs.readFileSync(input);
const lines = [`#pragma once`, `#include <stdint.h>`, `static const uint8_t ${symbol}[${bytes.length}] = {`];
for (let i = 0; i < bytes.length; i += 16)
  lines.push(`  ${[...bytes.subarray(i, i + 16)].map(n => `0x${n.toString(16).padStart(2, "0")}`).join(", ")},`);
lines.push(`};`, ``);
fs.mkdirSync(path.dirname(output), { recursive: true });
fs.writeFileSync(output, lines.join("\n"));
