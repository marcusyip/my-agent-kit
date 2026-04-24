# Contributing to my-agent-kit

## Adding a New Plugin

1. Create a directory at the repo root named after your plugin:

```
your-plugin/
├── .claude-plugin/
│   └── plugin.json        # Plugin manifest (name, version, description, agents, skills)
├── agents/                 # Agent definitions (optional)
├── skills/                 # Skill definitions (optional)
├── README.md               # User-facing documentation
└── LICENSE                 # MIT recommended
```

2. Register it in `.claude-plugin/marketplace.json` by adding an entry to the `plugins` array:

```json
{
  "name": "your-plugin",
  "version": "1.0.0",
  "description": "Brief description of what it does",
  "source": "./your-plugin"
}
```

3. Open a pull request with a description of what the plugin does and example output.

## Plugin Quality Bar

Your plugin should include:

- **README.md** with installation, usage examples, and what the plugin does
- **LICENSE** file (MIT recommended for consistency)
- **plugin.json** with accurate version, description, and keywords
- **Example output** or a benchmark showing the plugin works (can be in the PR description)

## Updating an Existing Plugin

1. Make your changes to the skill/agent definitions
2. Bump the version in both `plugin.json` and `.claude-plugin/marketplace.json`
3. Add a changelog entry in `CHANGELOG.md` under the new version
4. If SKILL.md exceeds 800 lines, extract reference material to separate files

## Development Workflow

1. Create a feature branch
2. Make changes
3. Test locally: `claude plugin install your-plugin@my-agent-kit`
4. Verify the skill/agent works as expected in Claude Code
5. Open a PR

## Guidelines

- Keep SKILL.md files under 800 lines — extract reference material to separate files
- One plugin per directory at the repo root
- Use [Keep a Changelog](https://keepachangelog.com/) format for changelog entries
- Be respectful in discussions and reviews

## Working on `tdd-contract-review`

Run artifacts (01-extraction, 02-audit, 03x-gaps-*, report, call trees) are
JSON-first: the `.json` is the source of truth; the sibling `.md` is a
rendered view produced by `tdd-contract-review/scripts/render.py`. Never
hand-edit a generated `.md`. To change what the report says, edit the JSON
and re-render.

A pre-commit hook catches drift — it re-renders each staged `.json` and
fails the commit if the on-disk `.md` differs from the render. Install it
once per clone:

```bash
tdd-contract-review/scripts/install-pre-commit-hook.sh
```

To check drift manually (e.g. in CI):

```bash
python3 tdd-contract-review/scripts/check_rendered_md.py           # all tracked
python3 tdd-contract-review/scripts/check_rendered_md.py --staged  # pre-commit
```
