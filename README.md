# Claude Code Herder

A Mac app to browse, search and resume your Claude Code and Codex sessions, instead of juggling terminal tabs.

![Claude Code Herder](docs/screenshot.jpg)

Each session is a card with its title, recap, dates, message count (token count for Codex) and cost.
Click one to resume it in a new [iTerm2](https://iterm2.com) tab, or jump to its tab if it's already running.

## Profiles

Each profile is a Claude Code config folder or a Codex home. With no config file, the app picks up
`~/.claude` ("Claude"), every `~/.claude-*` folder that has sessions (`~/.claude-work` → "work"),
and `~/.codex` ("Codex").

To name, order or color them, write `~/.config/claude-herder/profiles.json`:

```json
{
  "profiles": [
    { "label": "Personal", "dir": "~/.claude" },
    { "label": "Work", "dir": "~/.claude-work", "color": "#3B6EA8" },
    { "label": "Codex", "dir": "~/.codex", "tool": "codex" }
  ]
}
```

| Key       | Required | Meaning |
| --------- | -------- | ------- |
| `label`   | yes      | Name on the cards and in the filter |
| `dir`     | yes      | The config folder (`CLAUDE_CONFIG_DIR` / `CODEX_HOME`); absolute or `~/…` |
| `tool`    | no       | `claude` (default) or `codex` |
| `command` | no       | What starts the tool, typed into the new tab. Defaults to `claude` / `codex` for `~/.claude` / `~/.codex`, else to one that sets `CLAUDE_CONFIG_DIR` / `CODEX_HOME`. Set it to use your own alias, e.g. `"claude-work"` |
| `color`   | no       | Badge color as `#RRGGBB` |

Changes apply on the next reload (⌘R). A broken file shows under "files failed to load", and the
app falls back to the folders it finds on its own.

Sessions resume with `<command> --resume <id>` (Claude) or `<command> resume <id>` (Codex).

Search covers every transcript, including Codex's zstd-compressed rollouts.
Codex keeps no registry of running sessions, so Codex cards never show as open.

## Build

Needs macOS 14+, Xcode's Swift toolchain, iTerm2, and [ripgrep](https://github.com/BurntSushi/ripgrep) and zstd for search:

```sh
brew install ripgrep zstd
./build_app.sh && open 'Claude Code Herder.app'
```

The first click on a card asks for permission to control iTerm2.

Cost is estimated from Anthropic's and OpenAI's API list prices, subagents included. For Codex, each
thread is priced at the model it last used, and auto-review threads are left out: their model has
no list price.

## License

MIT
