const EXPENSE = "Expense";
const CREDIT = "Credit";

function amountOf(transaction) {
  const amount = Number(transaction?.amount || 0);
  return Number.isFinite(amount) ? amount : 0;
}

function shareholderIdOf(transaction) {
  return (
    transaction?.shareholderId ||
    transaction?.creditShareholderId ||
    transaction?.shareholder_id ||
    null
  );
}

function paidByIdOf(transaction) {
  return (
    transaction?.paidById ||
    transaction?.paidBy ||
    transaction?.paid_by ||
    null
  );
}

function explicitPaymentSourceOf(transaction) {
  return transaction?.paymentSource || transaction?.payment_source || null;
}

export function resolveExpensePaymentSource(transaction, partners = []) {
  const explicitSource = explicitPaymentSourceOf(transaction);
  if (explicitSource === "partner" || explicitSource === "credit_balance") {
    return explicitSource;
  }

  const paidById = paidByIdOf(transaction);
  const legacyDelvin = partners.find(
    (partner) => String(partner?.name || "").trim().toLowerCase() === "delvin"
  );

  // Before payment sources existed, every expense without a choice was stored
  // as Delvin. Preserve those rows and interpret that old default as the
  // common Credit Balance. Other historical payer selections were deliberate.
  if (!paidById || paidById === legacyDelvin?.id) return "credit_balance";
  return "partner";
}

export function matchesPaymentSourceScope(transaction, paymentSourceId, partners = []) {
  if (!paymentSourceId || paymentSourceId === "all") return true;

  // A manual credit belongs to both the contributing partner's history and
  // the Credit Balance it funds. This keeps both analytical views complete.
  if (transaction?.type === CREDIT) {
    return paymentSourceId === "credit_balance" ||
      shareholderIdOf(transaction) === paymentSourceId;
  }

  if (transaction?.type !== EXPENSE) return false;

  const source = resolveExpensePaymentSource(transaction, partners);
  if (paymentSourceId === "credit_balance") return source === "credit_balance";

  return source === "partner" && paidByIdOf(transaction) === paymentSourceId;
}

/**
 * Summarizes the supplied transaction set exactly once.
 *
 * Credits are manual funding. Expenses remain project expenses, while an
 * expense with a partner in Paid By is also that partner's direct funding.
 * The two sides of a directly funded expense cancel in net position, so it
 * never behaves like a cash deposit followed by a cash withdrawal.
 */
export function calculateFinancialSummary({ transactions = [], partners = [] } = {}) {
  const rowsById = new Map(
    partners.map((partner) => [
      partner.id,
      {
        id: partner.id,
        name: partner.name,
        manualCredit: 0,
        directExpensesPaid: 0,
        totalContribution: 0,
        relevantExpenses: 0,
        netPosition: 0,
        manualCreditCount: 0,
        directExpenseCount: 0
      }
    ])
  );

  let totalProjectExpenses = 0;
  let totalCreditBalanceExpenses = 0;
  let unassignedManualCredits = 0;
  let unassignedDirectExpenses = 0;

  for (const transaction of transactions) {
    const amount = amountOf(transaction);

    if (transaction?.type === CREDIT) {
      const partner = rowsById.get(shareholderIdOf(transaction));
      if (partner) {
        partner.manualCredit += amount;
        partner.manualCreditCount += 1;
      } else {
        unassignedManualCredits += amount;
      }
      continue;
    }

    if (transaction?.type === EXPENSE) {
      totalProjectExpenses += amount;
      if (resolveExpensePaymentSource(transaction, partners) === "credit_balance") {
        totalCreditBalanceExpenses += amount;
        continue;
      }
      const partner = rowsById.get(paidByIdOf(transaction));
      if (partner) {
        partner.directExpensesPaid += amount;
        partner.directExpenseCount += 1;
      } else {
        unassignedDirectExpenses += amount;
      }
    }
  }

  const rows = Array.from(rowsById.values()).map((row) => ({
    ...row,
    totalContribution: row.manualCredit + row.directExpensesPaid,
    relevantExpenses: row.directExpensesPaid,
    netPosition: row.manualCredit
  }));

  const totalManualCredits = rows.reduce((sum, row) => sum + row.manualCredit, 0);
  const totalDirectExpensesPaid = rows.reduce(
    (sum, row) => sum + row.directExpensesPaid,
    0
  );
  const totalContribution = totalManualCredits + totalDirectExpensesPaid;
  const netPosition = totalManualCredits + unassignedManualCredits - totalCreditBalanceExpenses;

  return {
    rows,
    byPartnerId: Object.fromEntries(rows.map((row) => [row.id, row])),
    totalManualCredits,
    totalDirectExpensesPaid,
    totalContribution,
    totalProjectExpenses,
    totalCreditBalanceExpenses,
    totalDebitsWithdrawals: totalProjectExpenses,
    netPosition,
    currentBalance: netPosition,
    unassignedManualCredits,
    unassignedDirectExpenses,
    transactionCount: transactions.length
  };
}

export function netPositionImpact(transaction, partners = []) {
  const amount = amountOf(transaction);
  if (transaction?.type === CREDIT) return amount;
  if (transaction?.type !== EXPENSE) return 0;
  return resolveExpensePaymentSource(transaction, partners) === "partner" ? 0 : -amount;
}
