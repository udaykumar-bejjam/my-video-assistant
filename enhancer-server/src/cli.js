#!/usr/bin/env node
import fs from "node:fs";
import { enhanceWithCursor } from "./enhance.js";

const inputPath = process.argv[2];
if (!inputPath) {
  console.error("Usage: npm run enhance -- <captions.json>");
  process.exit(1);
}

const input = JSON.parse(fs.readFileSync(inputPath, "utf8"));
const plan = await enhanceWithCursor(input);
console.log(JSON.stringify(plan, null, 2));
