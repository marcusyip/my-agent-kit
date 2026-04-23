import React from "react";
import { View, Text, FlatList } from "react-native";
import { useTransactions } from "../hooks/useTransactions";
import { Transaction, formatAmount } from "../models/Transaction";

interface Props {
  userId: string;
  baseUrl: string;
}

export function TransactionScreen(props: Props) {
  const { items, loading, error } = useTransactions(props.userId, props.baseUrl);

  if (loading) {
    return <Text>Loading…</Text>;
  }
  if (error) {
    return <Text>Error: {error.message}</Text>;
  }
  return (
    <View>
      <FlatList
        data={items}
        keyExtractor={(tx: Transaction) => tx.id}
        renderItem={({ item }) => <Text>{formatAmount(item)}</Text>}
      />
    </View>
  );
}
