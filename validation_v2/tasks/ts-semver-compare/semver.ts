// semver.ts — Semantic version comparison with built-in assertions.

interface SemVer {
  major: number;
  minor: number;
  patch: number;
}

function parseSemver(v: string): SemVer {
  const m = v.match(/^(\d+)\.(\d+)\.(\d+)$/);
  if (!m) throw new Error(`Invalid semver: ${v}`);
  return { major: +m[1], minor: +m[2], patch: +m[3] };
}

/**
 * Compare two semver strings.
 * Returns: -1 if a < b, 0 if a === b, 1 if a > b.
 */
function compareSemver(a: string, b: string): number {
  const va = parseSemver(a);
  const vb = parseSemver(b);

  if (va.major !== vb.major) return va.major < vb.major ? -1 : 1;
  if (va.minor !== vb.minor) return va.minor < vb.minor ? -1 : 1;
  if (va.patch !== vb.patch) return va.patch < vb.patch ? -1 : 1;
  return 0;
}

// --- Assertions ---

function assertEq(actual: number, expected: number, msg: string): void {
  if (actual !== expected) {
    throw new Error(`${msg}: expected ${expected}, got ${actual}`);
  }
}

// Basic ordering
assertEq(compareSemver("1.0.0", "2.0.0"), -1, "1.0.0 < 2.0.0");
assertEq(compareSemver("2.0.0", "1.0.0"), 1, "2.0.0 > 1.0.0");
assertEq(compareSemver("1.0.0", "1.0.0"), 0, "1.0.0 === 1.0.0");

// Minor version
assertEq(compareSemver("1.1.0", "1.2.0"), -1, "1.1.0 < 1.2.0");
assertEq(compareSemver("1.2.0", "1.1.0"), 1, "1.2.0 > 1.1.0");

// Patch version
assertEq(compareSemver("1.0.1", "1.0.2"), -1, "1.0.1 < 1.0.2");
assertEq(compareSemver("1.0.2", "1.0.1"), 1, "1.0.2 > 1.0.1");

// Major dominates minor
assertEq(compareSemver("2.0.0", "1.999.999"), 1, "2.0.0 > 1.999.999");

// Minor dominates patch
assertEq(compareSemver("1.1.0", "1.0.999"), 1, "1.1.0 > 1.0.999");

// Reverse symmetry
const a = compareSemver("3.2.1", "3.2.2");
assertEq(a, -1, "3.2.1 < 3.2.2");
assertEq(compareSemver("3.2.2", "3.2.1"), 1, "3.2.2 > 3.2.1");

// Invalid input should throw
try {
  compareSemver("1.0", "1.0.0");
  throw new Error("Expected error for invalid semver '1.0'");
} catch (e) {
  // expected
}

try {
  compareSemver("1.0.0", "abc");
  throw new Error("Expected error for invalid semver 'abc'");
} catch (e) {
  // expected
}

console.log("ts-semver-compare: all assertions passed.");
