/** Compare two semver strings. Returns -1, 0, or 1. */
function compare(a: string, b: string): number {
    const pa = a.split('.').map(Number);
    const pb = b.split('.').map(Number);
    for (let i = 0; i < 3; i++) {
        if (pa[i] > pb[i]) return 1;
        if (pa[i] < pb[i]) return -1;
    }
    return 0;
}

// Self-test
const assert = (cond: boolean, msg: string) => {
    if (!cond) throw new Error(`Assertion failed: ${msg}`);
};

assert(compare("1.2.3", "1.2.4") === -1, "1.2.3 < 1.2.4");
assert(compare("1.0.0", "1.0.0") === 0, "1.0.0 == 1.0.0");
assert(compare("2.0.0", "1.9.9") === 1, "2.0.0 > 1.9.9");
console.log("All assertions passed.");
