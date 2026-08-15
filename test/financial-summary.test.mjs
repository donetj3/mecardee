import assert from "node:assert/strict";
import test from "node:test";
import {
  calculateFinancialSummary,
  matchesPaymentSourceScope,
  netPositionImpact,
  resolveExpensePaymentSource
} from "../lib/financial-summary.mjs";

const partners = [
  { id: "delvin", name: "Delvin" },
  { id: "dandees", name: "Dandees" },
  { id: "dennys", name: "Dennys" }
];

const credit = (partnerId, amount, date = "2026-01-01") => ({
  type: "Credit",
  shareholderId: partnerId,
  amount,
  date
});

const expense = (partnerId, amount, date = "2026-01-01") => ({
  type: "Expense",
  paidById: partnerId,
  paymentSource: "partner",
  amount,
  date
});

const creditBalanceExpense = (amount, date = "2026-01-01") => ({
  type: "Expense",
  paidById: null,
  paymentSource: "credit_balance",
  amount,
  date
});

test("scenario 1: Delvin manual and direct funding are added once", () => {
  const summary = calculateFinancialSummary({
    partners,
    transactions: [credit("delvin", 1_000_000), expense("delvin", 200_000)]
  });

  assert.deepEqual(summary.byPartnerId.delvin, {
    id: "delvin",
    name: "Delvin",
    manualCredit: 1_000_000,
    directExpensesPaid: 200_000,
    totalContribution: 1_200_000,
    relevantExpenses: 200_000,
    netPosition: 1_000_000,
    manualCreditCount: 1,
    directExpenseCount: 1
  });
});

test("scenario 2: Dandees contribution totals four lakh", () => {
  const summary = calculateFinancialSummary({
    partners,
    transactions: [credit("dandees", 375_000), expense("dandees", 25_000)]
  });

  assert.equal(summary.byPartnerId.dandees.manualCredit, 375_000);
  assert.equal(summary.byPartnerId.dandees.directExpensesPaid, 25_000);
  assert.equal(summary.byPartnerId.dandees.totalContribution, 400_000);
});

test("scenario 3: Dennys manual credit works without a direct expense", () => {
  const summary = calculateFinancialSummary({
    partners,
    transactions: [credit("dennys", 500_000)]
  });

  assert.equal(summary.byPartnerId.dennys.manualCredit, 500_000);
  assert.equal(summary.byPartnerId.dennys.directExpensesPaid, 0);
  assert.equal(summary.byPartnerId.dennys.totalContribution, 500_000);
});

test("scenario 4: a direct expense is an expense and contribution, not manual credit", () => {
  const transaction = expense("delvin", 100);
  const summary = calculateFinancialSummary({ partners, transactions: [transaction] });

  assert.equal(summary.totalProjectExpenses, 100);
  assert.equal(summary.byPartnerId.delvin.manualCredit, 0);
  assert.equal(summary.byPartnerId.delvin.directExpensesPaid, 100);
  assert.equal(summary.byPartnerId.delvin.totalContribution, 100);
  assert.equal(summary.netPosition, 0);
  assert.equal(netPositionImpact(transaction, partners), 0);
});

test("scenario 5: a partner-only transaction set contains no other partner values", () => {
  const allTransactions = [
    credit("delvin", 10),
    expense("delvin", 5),
    credit("dandees", 20),
    expense("dandees", 7)
  ];
  const dandeesTransactions = allTransactions.filter(
    (transaction) =>
      transaction.shareholderId === "dandees" || transaction.paidById === "dandees"
  );
  const summary = calculateFinancialSummary({ partners, transactions: dandeesTransactions });

  assert.equal(summary.byPartnerId.dandees.totalContribution, 27);
  assert.equal(summary.byPartnerId.delvin.totalContribution, 0);
  assert.equal(summary.byPartnerId.dennys.totalContribution, 0);
});

test("scenario 6: overall totals equal the clean partner-wise breakdown", () => {
  const summary = calculateFinancialSummary({
    partners,
    transactions: [
      credit("delvin", 1_000_000),
      expense("delvin", 200_000),
      credit("dandees", 375_000),
      expense("dandees", 25_000),
      credit("dennys", 500_000)
    ]
  });

  assert.equal(summary.totalManualCredits, 1_875_000);
  assert.equal(summary.totalDirectExpensesPaid, 225_000);
  assert.equal(summary.totalContribution, 2_100_000);
  assert.equal(summary.totalProjectExpenses, 225_000);
  assert.equal(summary.netPosition, 1_875_000);
  assert.equal(
    summary.rows.reduce((sum, row) => sum + row.totalContribution, 0),
    summary.totalContribution
  );
});

test("legacy unassigned credits remain visible and an unassigned expense uses Credit Balance", () => {
  const summary = calculateFinancialSummary({
    partners,
    transactions: [
      { type: "Credit", amount: 50 },
      { type: "Expense", amount: 20 }
    ]
  });

  assert.equal(summary.unassignedManualCredits, 50);
  assert.equal(summary.unassignedDirectExpenses, 0);
  assert.equal(summary.totalCreditBalanceExpenses, 20);
  assert.equal(summary.totalContribution, 0);
  assert.equal(summary.netPosition, 30);
});

test("credit balance is the default expense source and reduces net position", () => {
  const transaction = creditBalanceExpense(100);
  const summary = calculateFinancialSummary({
    partners,
    transactions: [credit("delvin", 500), transaction]
  });

  assert.equal(summary.totalManualCredits, 500);
  assert.equal(summary.totalDirectExpensesPaid, 0);
  assert.equal(summary.totalCreditBalanceExpenses, 100);
  assert.equal(summary.totalContribution, 500);
  assert.equal(summary.netPosition, 400);
  assert.equal(netPositionImpact(transaction, partners), -100);
});

test("legacy Delvin payer values are interpreted as Credit Balance", () => {
  const legacyTransaction = {
    type: "Expense",
    paidById: "delvin",
    amount: 250
  };
  const summary = calculateFinancialSummary({
    partners,
    transactions: [legacyTransaction]
  });

  assert.equal(resolveExpensePaymentSource(legacyTransaction, partners), "credit_balance");
  assert.equal(summary.byPartnerId.delvin.directExpensesPaid, 0);
  assert.equal(summary.totalCreditBalanceExpenses, 250);
  assert.equal(summary.netPosition, -250);
});

test("an explicitly selected Delvin payer is a direct contribution", () => {
  const directTransaction = expense("delvin", 250);
  const summary = calculateFinancialSummary({
    partners,
    transactions: [directTransaction]
  });

  assert.equal(resolveExpensePaymentSource(directTransaction, partners), "partner");
  assert.equal(summary.byPartnerId.delvin.directExpensesPaid, 250);
  assert.equal(summary.byPartnerId.delvin.totalContribution, 250);
  assert.equal(summary.netPosition, 0);
});

test("a partner-paid bill is counted once and never moves Credit Balance", () => {
  const directBill = expense("dandees", 300);
  const summary = calculateFinancialSummary({
    partners,
    transactions: [
      credit("delvin", 1_000),
      creditBalanceExpense(200),
      directBill
    ]
  });

  assert.equal(summary.totalProjectExpenses, 500);
  assert.equal(summary.totalCreditBalanceExpenses, 200);
  assert.equal(summary.totalDirectExpensesPaid, 300);
  assert.equal(summary.byPartnerId.dandees.totalContribution, 300);
  assert.equal(summary.totalContribution, 1_300);
  assert.equal(summary.currentBalance, 800);
  assert.equal(netPositionImpact(directBill, partners), 0);
});

test("Credit Balance scope includes funding credits and balance-funded expenses", () => {
  const fundingCredit = credit("delvin", 500);
  const balanceBill = creditBalanceExpense(200);
  const directBill = expense("dandees", 300);

  assert.equal(matchesPaymentSourceScope(fundingCredit, "credit_balance", partners), true);
  assert.equal(matchesPaymentSourceScope(balanceBill, "credit_balance", partners), true);
  assert.equal(matchesPaymentSourceScope(directBill, "credit_balance", partners), false);
  assert.equal(matchesPaymentSourceScope(fundingCredit, "delvin", partners), true);
  assert.equal(matchesPaymentSourceScope(balanceBill, "delvin", partners), false);
});
