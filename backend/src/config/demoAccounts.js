// Demo accounts created by `npm run seed` (src/seed.js). Listed on the login screens in development mode only.
const DEMO_PASSWORD = 'password123';

const DEMO_ACCOUNTS = [
  { role: 'admin', name: 'Vendra Admin', email: 'admin@vendra.pk', note: 'Platform admin' },
  { role: 'vendor', name: 'Usman Tariq', email: 'usman@vendor.pk', note: 'Capital Electronics Hub, Blue Area, Islamabad' },
  { role: 'vendor', name: 'Ayesha Khan', email: 'ayesha@vendor.pk', note: "Ayesha's Boutique, Saddar, Rawalpindi" },
  { role: 'customer', name: 'Ahmed Raza', email: 'ahmed@customer.pk', note: 'F-7, Islamabad' },
  { role: 'customer', name: 'Fatima Ali', email: 'fatima@customer.pk', note: 'Satellite Town, Rawalpindi' },
  { role: 'rider', name: 'Bilal Hussain', email: 'bilal@rider.pk', note: 'G-9, Islamabad' },
  { role: 'rider', name: 'Hamza Sheikh', email: 'hamza@rider.pk', note: 'Saddar, Rawalpindi' },
].map((a) => ({ ...a, password: DEMO_PASSWORD }));

module.exports = { DEMO_ACCOUNTS, DEMO_PASSWORD };
