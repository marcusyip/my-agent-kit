# sample-app-ts

Minimal React Native-style TypeScript fixture used by the
`tdd-contract-review` plugin's LSP smoke tests. Ships **no** runtime
dependencies — `react` / `react-native` imports deliberately resolve to
"external" in the LSP walker so the fixture also exercises that code path.

## Layout

```
src/
├── screens/TransactionScreen.tsx   React Native function component (JSX view)
├── hooks/useTransactions.ts        custom hook wrapping the service
├── services/
│   ├── TransactionService.ts       class: instance + static methods,
│   │                                depends on ApiClient + Transaction model
│   └── ApiClient.ts                class: instance methods (GET, POST)
└── models/Transaction.ts           types + free functions (validator, formatter)
```

## What this fixture exercises

- **Free function** — `formatAmount`, `isSupportedCurrency`, `useTransactions`
- **Class instance method** — `TransactionService#fetchForUser`,
  `ApiClient#get`
- **Class static method** — `TransactionService.validate`
- **React function component** — `TransactionScreen`
- **Cross-file definition resolution** — `TransactionScreen` → hook → service
  → ApiClient + model, all local imports ts-server should follow
- **External resolution** — `useState`, `useEffect`, `View`, `Text`,
  `FlatList` all resolve outside the project root (or not at all), and the
  walker tags them `[external]` / `[unresolved]`

## Running the call-tree walker

```bash
python tdd-contract-review/scripts/lsp_tree.py \
  --lang ts \
  --project tdd-contract-review/benchmark/sample-app-ts \
  --file src/screens/TransactionScreen.tsx \
  --symbol TransactionScreen \
  --depth 4
```

See `tdd-contract-review/scripts/lsp_tree.py --help` for more options
(`--format markdown` for the legacy indented-bullet view — json is the default, `--scope local`, `--run-dir DIR`).
