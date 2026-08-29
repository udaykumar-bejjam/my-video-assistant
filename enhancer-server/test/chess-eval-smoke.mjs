import { categoryFromDeltaCp, enrichCategories } from "../src/chessEval.js";

function assert(cond, msg) {
  if (!cond) {
    console.error("FAIL", msg);
    process.exitCode = (process.exitCode || 0) + 1;
  } else {
    console.log("PASS", msg);
  }
}

assert(categoryFromDeltaCp(-600) === "blunder", "queen loss → blunder");
assert(categoryFromDeltaCp(-250) === "mistake", "minor hang → mistake");
assert(categoryFromDeltaCp(-100) === "inaccuracy", "small loss → inaccuracy");
assert(categoryFromDeltaCp(550, { isCapture: false }) === "brilliant", "big non-capture gain → brilliant");
assert(categoryFromDeltaCp(350) === "great", "big gain → great");
assert(categoryFromDeltaCp(150) === "good", "solid gain → good");
assert(categoryFromDeltaCp(10, { gaveCheck: true }) === "critical", "check → critical");
assert(categoryFromDeltaCp(50) === "interesting", "small plus → interesting");
assert(categoryFromDeltaCp(0) === "normal", "equal → normal");

const enriched = enrichCategories([
  { category: "blunder", deltaCp: 0 },
  { category: "normal", deltaCp: -300, isCapture: false },
  { category: "normal", deltaCp: 0, gaveCheck: true },
]);
assert(enriched[0].evalSource === "annotation", "keep NAG/annotation");
assert(enriched[0].category === "blunder", "annotation preserved");
assert(enriched[1].category === "mistake", "heuristic fills normal");
assert(enriched[1].evalSource === "heuristic", "heuristic source tagged");
assert(enriched[2].category === "critical", "check heuristic");

if (process.exitCode) {
  console.error(`chess-eval smoke: ${process.exitCode} failure(s)`);
  process.exit(1);
}
console.log("OK — chess-eval smoke");
