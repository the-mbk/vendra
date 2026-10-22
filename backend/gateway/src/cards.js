// ══════════════════════════════════════════════════════════════
// Vendra Pay test cards. Only these numbers are accepted, so nobody can
// type a real card into the sandbox by mistake. Any future expiry date
// and any 3-digit CVC work.
// ══════════════════════════════════════════════════════════════

const SANDBOX_OTP = '123456';

/**
 * behaviour:
 *   success          charges and payouts succeed
 *   otp              charge needs a one-time password (3-D Secure); payouts succeed
 *   declined         charges are declined; payouts to it fail
 *   insufficient     charges fail for lack of funds; payouts succeed
 *   expired          charges fail as expired
 *   incorrect_cvc    charges fail on the CVC check
 *   payout_fails     charges succeed; payouts are accepted, then bounce
 */
const TEST_CARDS = [
  { number: '4242424242424242', brand: 'visa', funding: 'credit', behaviour: 'success', label: 'Payment succeeds' },
  { number: '5555555555554444', brand: 'mastercard', funding: 'credit', behaviour: 'success', label: 'Payment succeeds' },
  { number: '4000056655665556', brand: 'visa', funding: 'debit', behaviour: 'success', label: 'Debit card — payments and payouts succeed' },
  { number: '5200828282828210', brand: 'mastercard', funding: 'debit', behaviour: 'success', label: 'Debit card — payments and payouts succeed' },
  { number: '4000002760003184', brand: 'visa', funding: 'credit', behaviour: 'otp', label: `Asks for a one-time password (use ${SANDBOX_OTP})` },
  { number: '4000000000000002', brand: 'visa', funding: 'credit', behaviour: 'declined', label: 'Payment declined; payouts fail' },
  { number: '4000000000009995', brand: 'visa', funding: 'credit', behaviour: 'insufficient', label: 'Declined: insufficient funds' },
  { number: '4000000000000069', brand: 'visa', funding: 'credit', behaviour: 'expired', label: 'Declined: expired card' },
  { number: '4000000000000127', brand: 'visa', funding: 'credit', behaviour: 'incorrect_cvc', label: 'Declined: incorrect CVC' },
  { number: '4000000000000119', brand: 'visa', funding: 'debit', behaviour: 'payout_fails', label: 'Payments succeed; payouts bounce after processing' },
];

const BY_NUMBER = new Map(TEST_CARDS.map((c) => [c.number, c]));

function luhnValid(number) {
  let sum = 0;
  let double = false;
  for (let i = number.length - 1; i >= 0; i--) {
    let d = Number(number[i]);
    if (double) {
      d *= 2;
      if (d > 9) d -= 9;
    }
    sum += d;
    double = !double;
  }
  return sum % 10 === 0;
}

/** What happens when this card is charged: null = success, otherwise a decline */
const CHARGE_DECLINES = {
  declined: { code: 'card_declined', message: 'Your card was declined.' },
  insufficient: { code: 'insufficient_funds', message: 'Your card has insufficient funds.' },
  expired: { code: 'expired_card', message: 'Your card has expired.' },
  incorrect_cvc: { code: 'incorrect_cvc', message: "Your card's security code is incorrect." },
};

/** What happens when money is paid out to this card: null = paid, otherwise the failure */
const PAYOUT_FAILURES = {
  declined: { code: 'card_declined', message: 'The receiving card declined the payout.' },
  payout_fails: { code: 'could_not_process', message: "The receiving bank couldn't process this payout." },
};

module.exports = { TEST_CARDS, BY_NUMBER, SANDBOX_OTP, luhnValid, CHARGE_DECLINES, PAYOUT_FAILURES };
