# my-agent-kit

A curated collection of [Claude Code](https://docs.anthropic.com/en/docs/claude-code) plugins for development workflow automation.

## Plugins

### [tdd-contract-review](./tdd-contract-review/)

Contract-based test quality reviewer. Extracts contracts from source code (API request/response fields, DB model fields, outbound API params, UI component props), maps test coverage per field, identifies gaps, scores quality across 6 weighted categories, and auto-generates test stubs for missing coverage.

**Highlights:**
- Fintech domain auto-detection with 8-dimension analysis (money/precision, idempotency, state machines, concurrency, security, and more)
- Supports RSpec, Go testing, Jest/Vitest, and pytest
- Weighted scoring rubric (0-10) with calibrated verdicts
- Auto-generated test stubs that follow your project's existing patterns

```
/tdd-contract-review                         # PR-scoped (on branch) or entire project
/tdd-contract-review src/auth/               # Review tests for a specific module
/tdd-contract-review src/services/payment.ts # Review tests for a source file
/tdd-contract-review quick                   # Quick mode: score + HIGH gaps only
```

See the full documentation in [tdd-contract-review/README.md](./tdd-contract-review/README.md).

## Installation

Add this repo as a Claude Code plugin marketplace, then install plugins from it:

```bash
# Register the marketplace
claude plugin marketplace add github:marcusyip/my-agent-kit

# Install the plugin
claude plugin install tdd-contract-review@my-agent-kit
```

Or install from a local clone:

```bash
git clone https://github.com/marcusyip/my-agent-kit.git
claude plugin marketplace add ./my-agent-kit
claude plugin install tdd-contract-review@my-agent-kit
```

## Repository Structure

```
my-agent-kit/
├── .claude-plugin/
│   └── marketplace.json          # Marketplace manifest
├── tdd-contract-review/          # Plugin directory
│   ├── .claude-plugin/
│   │   └── plugin.json           # Plugin manifest
│   ├── skills/                   # Skill definitions
│   ├── benchmark/                # Test suite with sample app and version reports
│   ├── README.md
│   └── LICENSE
├── CHANGELOG.md
├── CONTRIBUTING.md
├── LICENSE
└── README.md
```

Each plugin lives in its own directory at the repo root with its own `.claude-plugin/plugin.json`, README, and LICENSE. See [CONTRIBUTING.md](./CONTRIBUTING.md) for how to add a new plugin.

## Contributing

Contributions welcome. See [CONTRIBUTING.md](./CONTRIBUTING.md) for guidelines on adding or updating plugins.

## License

[MIT](./LICENSE)
