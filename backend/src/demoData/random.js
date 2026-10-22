// Seeded random numbers, so the demo dataset comes out the same on every run

function createRandom(seed = 20261013) {
  let a = seed >>> 0;
  // mulberry32
  const next = () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };

  const r = {
    next,
    /** Integer in [min, max] */
    int: (min, max) => min + Math.floor(next() * (max - min + 1)),
    float: (min, max) => min + next() * (max - min),
    chance: (p) => next() < p,
    pick: (list) => list[Math.floor(next() * list.length)],
    /** items: [[value, weight], …] */
    weighted(items) {
      const total = items.reduce((s, [, w]) => s + w, 0);
      let x = next() * total;
      for (const [value, w] of items) {
        x -= w;
        if (x < 0) return value;
      }
      return items[items.length - 1][0];
    },
    shuffle(list) {
      const out = [...list];
      for (let i = out.length - 1; i > 0; i--) {
        const j = Math.floor(next() * (i + 1));
        [out[i], out[j]] = [out[j], out[i]];
      }
      return out;
    },
    sample: (list, n) => r.shuffle(list).slice(0, Math.min(n, list.length)),
    digits: (n) => Array.from({ length: n }, () => Math.floor(next() * 10)).join(''),
  };
  return r;
}

module.exports = { createRandom };
