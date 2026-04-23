import { ApiClient } from "./ApiClient";
import {
  Transaction,
  isSupportedCurrency,
} from "../models/Transaction";

export class TransactionService {
  private api: ApiClient;

  constructor(baseUrl: string) {
    this.api = new ApiClient(baseUrl);
  }

  async fetchForUser(userId: string): Promise<Transaction[]> {
    const path = this.userPath(userId);
    const raw = await this.api.get<Transaction[]>(path);
    return raw.filter((tx) => TransactionService.validate(tx));
  }

  async create(tx: Transaction): Promise<Transaction> {
    if (!TransactionService.validate(tx)) {
      throw new Error("invalid transaction");
    }
    return this.api.post<Transaction>("/transactions", tx);
  }

  static validate(tx: Transaction): boolean {
    return tx.amount > 0 && isSupportedCurrency(tx.currency);
  }

  private userPath(userId: string): string {
    return `/users/${userId}/transactions`;
  }
}
