# Claude Usage Meter

A minimal take on [Claude-Usage-Tracker](https://github.com/hamed-elfayome/Claude-Usage-Tracker):
your Claude plan usage in the macOS menu bar and the Claude Code status line.

Each window (5-hour and weekly) is a bar filled to your utilization, with a vertical
marker showing how much of the window has elapsed — fill past the marker means
you're burning faster than even pace.

The marker is only a pace guide — you can keep using Claude past it; the real limit is
the end of the bar. So bars are **green** at or behind the marker, **orange** once past
it (on track to run out before reset), and **red** when past it *and* at 85%+ of the bar. At 100% the window shows as blocked (`!!` in the menu bar,
`LIMIT` in the status line) with the time it comes back.

## Screenshots

**Menu bar**: the 5-hour window on top, weekly below. The white tick is the elapsed-time marker.

![Menu bar states](docs/menubar-states.png)

**Popover**: click the bars for exact numbers, reset times, and how far ahead of pace you are.

<img src="docs/popover.png" alt="Popover" width="280">

**Claude Code status line**

![Status line](docs/statusline.png)

## Install

```sh
./scripts/build-app.sh          # builds, installs to ~/Applications, launches (registers at login)
./scripts/install-statusline.sh # installs ~/.claude/usage-meter-statusline.sh into settings.json
```

Only the Command Line Tools are needed (no Xcode). To regenerate the screenshots
from sample data, run `./scripts/screenshots.sh`.

## How it works

- The app reads Claude Code's OAuth token from the Keychain (`Claude Code-credentials`)
  via `/usr/bin/security` and polls `https://api.anthropic.com/api/oauth/usage` every 60s.
  It never refreshes the token (that would sign Claude Code out); if it's expired,
  values go dim until Claude Code refreshes it.
- After each fetch it writes `~/.claude/usage-meter-cache.json`.
- The status line uses the `rate_limits` Claude Code passes on stdin, falling back to
  that cache (if under 10 minutes old).
