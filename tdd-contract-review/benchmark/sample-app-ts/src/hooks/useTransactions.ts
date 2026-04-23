import { useEffect, useState } from "react";
import { TransactionService } from "../services/TransactionService";
import { Transaction } from "../models/Transaction";

export function useTransactions(userId: string, baseUrl: string) {
  const [items, setItems] = useState<Transaction[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);

  useEffect(() => {
    const svc = new TransactionService(baseUrl);
    setLoading(true);
    svc
      .fetchForUser(userId)
      .then((txs) => {
        setItems(txs);
        setLoading(false);
      })
      .catch((err) => {
        setError(err);
        setLoading(false);
      });
  }, [userId, baseUrl]);

  return { items, loading, error };
}
