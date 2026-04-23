export type Currency = "USD" | "EUR" | "JPY" | "GBP";

export interface Transaction {
  id: string;
  userId: string;
  amount: number;
  currency: Currency;
  createdAt: string;
}

export function isSupportedCurrency(c: string): c is Currency {
  return c === "USD" || c === "EUR" || c === "JPY" || c === "GBP";
}

export function formatAmount(tx: Transaction): string {
  return `${tx.currency} ${tx.amount.toFixed(2)}`;
}
