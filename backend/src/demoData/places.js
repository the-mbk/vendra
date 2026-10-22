// Areas of Islamabad and Rawalpindi used by the demo dataset (approximate centres).
// market: where shops are; homes: where customers and riders live.

const AREAS = [
  // Islamabad
  { name: 'Blue Area', city: 'Islamabad', lat: 33.7104, lng: 73.0560, market: 'Jinnah Avenue, Blue Area', homes: false },
  { name: 'F-6', city: 'Islamabad', lat: 33.7290, lng: 73.0750, market: 'Super Market, F-6 Markaz', subs: ['F-6/1', 'F-6/2', 'F-6/3', 'F-6/4'] },
  { name: 'F-7', city: 'Islamabad', lat: 33.7203, lng: 73.0560, market: 'Jinnah Super Market, F-7 Markaz', subs: ['F-7/1', 'F-7/2', 'F-7/3', 'F-7/4'] },
  { name: 'F-8', city: 'Islamabad', lat: 33.7085, lng: 73.0380, market: 'F-8 Markaz', subs: ['F-8/1', 'F-8/2', 'F-8/3', 'F-8/4'] },
  { name: 'F-10', city: 'Islamabad', lat: 33.6955, lng: 73.0130, market: 'F-10 Markaz', subs: ['F-10/1', 'F-10/2', 'F-10/3', 'F-10/4'] },
  { name: 'F-11', city: 'Islamabad', lat: 33.6845, lng: 72.9880, market: 'F-11 Markaz', subs: ['F-11/1', 'F-11/2', 'F-11/3', 'F-11/4'] },
  { name: 'G-6', city: 'Islamabad', lat: 33.7095, lng: 73.0920, market: 'Melody Market, G-6 Markaz', subs: ['G-6/1', 'G-6/2', 'G-6/3', 'G-6/4'] },
  { name: 'G-8', city: 'Islamabad', lat: 33.6935, lng: 73.0480, market: 'G-8 Markaz', subs: ['G-8/1', 'G-8/2', 'G-8/3', 'G-8/4'] },
  { name: 'G-9', city: 'Islamabad', lat: 33.6880, lng: 73.0290, market: 'Karachi Company, G-9 Markaz', subs: ['G-9/1', 'G-9/2', 'G-9/3', 'G-9/4'] },
  { name: 'G-10', city: 'Islamabad', lat: 33.6770, lng: 73.0150, market: 'G-10 Markaz', subs: ['G-10/1', 'G-10/2', 'G-10/3', 'G-10/4'] },
  { name: 'G-11', city: 'Islamabad', lat: 33.6680, lng: 73.0000, market: 'G-11 Markaz', subs: ['G-11/1', 'G-11/2', 'G-11/3', 'G-11/4'] },
  { name: 'G-13', city: 'Islamabad', lat: 33.6480, lng: 72.9690, market: 'G-13 Markaz', subs: ['G-13/1', 'G-13/2', 'G-13/3', 'G-13/4'] },
  { name: 'I-8', city: 'Islamabad', lat: 33.6670, lng: 73.0750, market: 'I-8 Markaz', subs: ['I-8/1', 'I-8/2', 'I-8/3', 'I-8/4'] },
  { name: 'I-10', city: 'Islamabad', lat: 33.6480, lng: 73.0400, market: 'I-10 Markaz', subs: ['I-10/1', 'I-10/2', 'I-10/3', 'I-10/4'] },
  { name: 'E-11', city: 'Islamabad', lat: 33.6990, lng: 72.9740, market: 'E-11 Markaz', subs: ['E-11/1', 'E-11/2', 'E-11/3', 'E-11/4'] },
  { name: 'DHA Phase 2', city: 'Islamabad', lat: 33.5290, lng: 73.1580, market: 'Sector J Commercial, DHA Phase 2', subs: ['Sector A', 'Sector C', 'Sector E', 'Sector J'] },
  { name: 'PWD Housing Society', city: 'Islamabad', lat: 33.5720, lng: 73.1450, market: 'PWD Main Boulevard', subs: ['Block A', 'Block B', 'Block C', 'Block D'] },
  { name: 'Gulberg Greens', city: 'Islamabad', lat: 33.6000, lng: 73.1650, market: 'Gulberg Business Square', subs: ['Block A', 'Block B', 'Block C'] },
  // Rawalpindi
  { name: 'Saddar', city: 'Rawalpindi', lat: 33.5973, lng: 73.0479, market: 'Bank Road, Saddar', subs: ['Kashmir Road', 'Haider Road', 'Adamjee Road'] },
  { name: 'Raja Bazaar', city: 'Rawalpindi', lat: 33.6136, lng: 73.0647, market: 'Raja Bazaar', homes: false },
  { name: 'Committee Chowk', city: 'Rawalpindi', lat: 33.6176, lng: 73.0680, market: 'Murree Road, Committee Chowk', homes: false },
  { name: 'Satellite Town', city: 'Rawalpindi', lat: 33.6380, lng: 73.0710, market: 'Commercial Market, Satellite Town', subs: ['A Block', 'B Block', 'C Block', 'D Block', 'E Block', 'F Block'] },
  { name: '6th Road', city: 'Rawalpindi', lat: 33.6440, lng: 73.0770, market: '6th Road, Murree Road', subs: ['Shamsabad', 'Muslim Town'] },
  { name: 'Chaklala Scheme III', city: 'Rawalpindi', lat: 33.5850, lng: 73.0870, market: 'Commercial Area, Chaklala Scheme III', subs: ['Street 1-10', 'Street 11-20', 'Street 21-30'] },
  { name: 'Westridge', city: 'Rawalpindi', lat: 33.6050, lng: 73.0150, market: 'Westridge Bazaar', subs: ['Westridge I', 'Westridge II', 'Westridge III'] },
  { name: 'Peshawar Road', city: 'Rawalpindi', lat: 33.6090, lng: 73.0300, market: 'Peshawar Road', subs: ['Gulistan Colony', 'Lalkurti'] },
  { name: 'Bahria Town Phase 7', city: 'Rawalpindi', lat: 33.5270, lng: 73.0950, market: 'Spring North Commercial, Bahria Town Phase 7', subs: ['Phase 7', 'Phase 8', 'Phase 4'] },
  { name: 'Tench Bhatta', city: 'Rawalpindi', lat: 33.5880, lng: 73.0560, market: 'Tench Bhatta Bazaar', subs: ['Gulshanabad', 'Tench Bhatta'] },
];

const MARKETS = AREAS;
const NEIGHBOURHOODS = AREAS.filter((a) => a.homes !== false);

const KM_PER_DEG_LAT = 111.32;

/** A point near the area centre, up to `radiusKm` away */
function pointIn(r, area, radiusKm = 0.6) {
  const d = Math.sqrt(r.next()) * radiusKm;
  const angle = r.next() * 2 * Math.PI;
  const lat = area.lat + (d * Math.cos(angle)) / KM_PER_DEG_LAT;
  const lng = area.lng + (d * Math.sin(angle)) / (KM_PER_DEG_LAT * Math.cos((area.lat * Math.PI) / 180));
  return { lat: Number(lat.toFixed(6)), lng: Number(lng.toFixed(6)) };
}

function homeAddress(r, area) {
  const sub = area.subs ? r.pick(area.subs) : area.name;
  if (area.city === 'Islamabad' && /^[EFGI]-\d+/.test(area.name)) {
    return `House ${r.int(1, 1200)}, Street ${r.int(1, 90)}, ${sub}, Islamabad`;
  }
  return `House ${r.int(1, 900)}, Street ${r.int(1, 40)}, ${sub}, ${area.name}, ${area.city}`;
}

function shopAddress(r, area) {
  return `Shop ${r.int(1, 160)}, ${area.market}, ${area.city}`;
}

module.exports = { AREAS, MARKETS, NEIGHBOURHOODS, pointIn, homeAddress, shopAddress };
