// ══════════════════════════════════════════════════════════════
// Privacy helpers: each party gets the least personal data it needs.
//   shortName    other people are named "Ayesha K." (first name, surname initial)
//   contactWhile a phone number is only sent while the order is in progress,
//                so a finished order leaves no way to reach the other person
// The apps show the numbers they do get masked (0312-***566); only the
// call button dials them.
// ══════════════════════════════════════════════════════════════

/** "Ayesha Khan" → "Ayesha K."; a missing name → fallback */
function shortName(fullName, fallback = null) {
  const parts = String(fullName || '').trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return fallback;
  return parts.length > 1 ? `${parts[0]} ${parts[parts.length - 1][0]}.` : parts[0];
}

const FINISHED = ['delivered', 'cancelled'];

/** The phone number while the order is still open, otherwise null */
function contactWhile(status, phone) {
  return FINISHED.includes(status) ? null : phone || null;
}

module.exports = { shortName, contactWhile };
