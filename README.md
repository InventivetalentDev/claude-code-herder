# Claude Herder

A Mac app to browse and resume Claude Code sessions, instead of juggling terminal tabs.

Reads transcripts from `~/.claude/projects`; **Open** resumes a session in a new Ghostty tab.

```sh
./build_app.sh && open ClaudeHerder.app
swift test   # includes a smoke test that parses every local transcript
```

Cost is the Anthropic API list price, so it's an estimate if you're on Bedrock or a subscription.
