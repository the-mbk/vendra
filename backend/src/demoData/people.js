// Names, phone numbers, CNICs and store names for the demo dataset

const MALE = [
  'Muhammad', 'Ahmed', 'Ali', 'Hassan', 'Hussain', 'Hamza', 'Bilal', 'Usman', 'Umar', 'Zain', 'Saad', 'Faisal',
  'Imran', 'Kamran', 'Asad', 'Shahid', 'Tariq', 'Waqas', 'Adeel', 'Junaid', 'Fahad', 'Danish', 'Haris', 'Arsalan',
  'Rizwan', 'Salman', 'Noman', 'Taimoor', 'Waleed', 'Zubair', 'Yasir', 'Sohail', 'Naveed', 'Farhan', 'Shoaib',
  'Talha', 'Hammad', 'Abdullah', 'Ibrahim', 'Mustafa', 'Owais', 'Sami', 'Raheel', 'Atif', 'Babar', 'Qasim',
];
const FEMALE = [
  'Ayesha', 'Fatima', 'Zainab', 'Maryam', 'Hira', 'Sana', 'Amna', 'Mahnoor', 'Iqra', 'Rabia', 'Sadia', 'Saba',
  'Nida', 'Aiman', 'Hafsa', 'Laiba', 'Areeba', 'Komal', 'Mehwish', 'Sidra', 'Zara', 'Anum', 'Kiran', 'Bushra',
  'Asma', 'Noor', 'Eman', 'Alishba', 'Javeria', 'Rida', 'Mariam', 'Khadija',
];
const LAST = [
  'Khan', 'Ahmed', 'Malik', 'Butt', 'Raja', 'Abbasi', 'Qureshi', 'Chaudhry', 'Sheikh', 'Hussain', 'Mirza', 'Awan',
  'Satti', 'Janjua', 'Kayani', 'Bhatti', 'Iqbal', 'Siddiqui', 'Hashmi', 'Gillani', 'Shah', 'Rana', 'Mughal',
  'Akhtar', 'Javed', 'Zafar', 'Aslam', 'Riaz', 'Tanoli', 'Durrani', 'Afridi', 'Minhas', 'Gondal', 'Warraich',
];

const MOBILE_PREFIXES = ['0300', '0301', '0302', '0303', '0305', '0308', '0309', '0312', '0313', '0314', '0315',
  '0321', '0322', '0323', '0331', '0332', '0333', '0334', '0335', '0336', '0345', '0346', '0347'];

/** { full, first, last, female } */
function personName(r, { female = r.chance(0.42) } = {}) {
  const first = r.pick(female ? FEMALE : MALE);
  const last = r.pick(LAST);
  return { first, last, female, full: `${first} ${last}` };
}

const phone = (r) => `${r.pick(MOBILE_PREFIXES)}-${r.digits(7)}`;
/** Islamabad CNICs start 61101, Rawalpindi 37405 */
const cnic = (r, city) => `${city === 'Islamabad' ? '61101' : '37405'}-${r.digits(7)}-${r.int(1, 9)}`;

/** Unique email in the reserved demo domain (never a real inbox) */
function makeEmails() {
  const used = new Map();
  return (first, last) => {
    const base = `${first}.${last}`.toLowerCase().replace(/[^a-z.]/g, '');
    const n = (used.get(base) || 0) + 1;
    used.set(base, n);
    return `${base}${n === 1 ? '' : n}@demo.vendra.pk`;
  };
}

/** Store types: which catalogue groups they stock and how common they are */
const STORE_TYPES = {
  grocery: { weight: 30, groups: ['groceries'], names: ['Mart', 'Super Store', 'General Store', 'Kiryana', 'Fresh Mart', 'Cash & Carry'], products: [12, 24] },
  electronics: { weight: 20, groups: ['smartphones', 'laptops', 'tablets', 'mobile-accessories'], names: ['Mobile Zone', 'Electronics', 'Gadget Hub', 'Mobile Centre', 'Tech Store', 'Digital World'], products: [10, 22] },
  fashion: { weight: 25, groups: ['mens-shirts', 'mens-shoes', 'mens-watches', 'womens-bags', 'womens-dresses', 'womens-jewellery', 'womens-shoes', 'womens-watches', 'tops', 'sunglasses'], names: ['Boutique', 'Collection', 'Fashion House', 'Clothing', 'Style Studio', 'Garments'], products: [12, 25] },
  beauty: { weight: 10, groups: ['beauty', 'fragrances', 'skin-care'], names: ['Cosmetics', 'Beauty Store', 'Perfumery', 'Beauty Bar'], products: [8, 13] },
  home: { weight: 10, groups: ['furniture', 'home-decoration', 'kitchen-accessories'], names: ['Home Store', 'Crockery House', 'Home & Kitchen', 'Interiors', 'Decor'], products: [10, 22] },
  sports: { weight: 5, groups: ['sports-accessories'], names: ['Sports', 'Sports Centre', 'Fitness Store'], products: [8, 15] },
};

const STORE_PREFIXES = ['Al-Madina', 'Al-Rehman', 'Bismillah', 'Capital', 'Margalla', 'Rawal', 'Pindi', 'Islamabad',
  'Faisal', 'Shaheen', 'Al-Habib', 'Madni', 'Royal', 'City', 'Star', 'New', 'Sadiq', 'Galaxy', 'Prime', 'Hilltop',
  'Potohar', 'Sitara', 'Noor', 'Green Valley', 'Metro', 'Hayat', 'Kohsar', 'Daman-e-Koh', 'Pak', 'Crescent'];

module.exports = { personName, phone, cnic, makeEmails, STORE_TYPES, STORE_PREFIXES };
