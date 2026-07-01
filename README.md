<div align="center">

# 🪙 Tokenholic

**See what your AI coding subscription is _actually_ earning you.**

[![GitHub stars](https://img.shields.io/github/stars/conol-ai/tokenholic?style=flat&logo=github&color=2ea043)](https://github.com/conol-ai/tokenholic/stargazers)
[![Latest release](https://img.shields.io/github/v/release/conol-ai/tokenholic?logo=github&color=2ea043)](https://github.com/conol-ai/tokenholic/releases/latest)
[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue)](LICENSE)
[![Platform: macOS 14+ · universal](https://img.shields.io/badge/macOS-14%2B%20·%20universal-555)](#requirements)
[![Validated against ccusage](https://img.shields.io/badge/validated%20against-ccusage-brightgreen)](https://github.com/ryoppippi/ccusage)

[![Download for macOS](https://img.shields.io/badge/Download_for_macOS-2ea043?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/conol-ai/tokenholic/releases/latest)
[![Star this repo](https://img.shields.io/badge/%E2%98%85_Star_this_repo-1f6feb?style=for-the-badge&logo=github&logoColor=white)](https://github.com/conol-ai/tokenholic)
[![tokenholic.app](https://img.shields.io/badge/%F0%9F%8C%90_tokenholic.app-30363d?style=for-the-badge)](https://tokenholic.app)

_If Tokenholic shows you a number you like, a ★ helps other developers find it._

<img src="site/demo.gif" width="480"
     alt="Tokenholic menubar demo: net earnings ticking up to +$371.40 with a daily API-value sparkline filling in, live as a coding session runs." />

<sub>Live in your menubar — the number moves as you code. (<a href="site/screenshot.png">static screenshot</a>)</sub>

</div>

Your AI coding plan probably isn't a cost — it's a **profit center**. Tokenholic
prices every token you burn in **Claude Code** and **Codex** at what the provider's
API _would_ have charged, subtracts your flat monthly subscription, and shows the
difference live in your menubar. A heavy month can read **+$371.40 net on a $20 plan**.

It's [**ccusage**](https://github.com/ryoppippi/ccusage), but live in your menubar and
framed as subscription **ROI** — same local logs, same LiteLLM price table, reconciled
to the cent.

The headline number is your **net earnings this billing cycle**:

```
API-equivalent cost of this cycle's tokens  −  your monthly subscription price
```

## Supported tools

| Tool | Source | Status |
|------|--------|--------|
| **Claude Code** | `~/.claude/projects/**/*.jsonl` (local) | ✅ validated against ccusage to the cent |
| **Codex** | `~/.codex/sessions/**/*.jsonl` (local) | ✅ OpenAI sessions |
| **Gemini CLI** | `~/.gemini/telemetry.log` (local) | ✅ opt-in — [enable local telemetry](https://google-gemini.github.io/gemini-cli/docs/cli/telemetry.html) |
| **Cursor** | dashboard API (cookie) | ▢ planned (experimental) |

Pricing comes from the same [LiteLLM price table](https://github.com/BerriAI/litellm)
ccusage uses (fetched live, cached 24h, with an embedded offline fallback), keyed
by exact model id. The 5m/1h prompt-cache split is priced separately, matching
Anthropic's billing.

## Install

**Homebrew (recommended)** — the native one-command path for the terminal crowd:

```sh
brew tap conol-ai/tokenholic https://github.com/conol-ai/tokenholic
brew install --cask tokenholic
```

Upgrade any time with `brew upgrade --cask tokenholic` to stay on the latest pricing logic.

**Direct download** — grab the latest signed `.dmg` from the
[Releases page](https://github.com/conol-ai/tokenholic/releases/latest).

**Build from source** — see [Requirements](#requirements) and [Build & run](#build--run) below.

## Requirements

- macOS 14+
- Xcode / Swift 6 toolchain

## Build & run

```sh
make          # build, assemble, and ad-hoc-sign Tokenholic.app
make run      # build and launch
```

It runs as a menubar agent (no Dock icon). Click the menubar item for the
popover: per-tool earnings cards, a daily-value sparkline, the last-5h value,
and Settings (plan prices, billing day, launch-at-login).

### Debug / verify

```sh
.build/release/Tokenholic --dump   # prints the full pipeline + a per-model
                                # breakdown for cross-checking against ccusage,
                                # plus an incremental-store idempotency check
```

## Architecture

```
Collectors  →  Normalizer  →  PricingEngine  →  EarningsCalculator  →  AppModel → UI
(per tool)     (dedup,        (LiteLLM rates,   (monthly cycle,         (FSEvents-
               drop synth)    cache-aware)      blended, daily)         driven)
```

- **Collectors** (`UsageCollector`): `ClaudeUsageStore` (incremental, append-only
  tail reads via byte offsets), `CodexCollector` (cumulative `total_token_usage`
  deltas). New tools drop in behind the protocol.
- **Normalizer**: dedups Claude records on `(messageId, requestId)`, drops
  `<synthetic>`.
- **PricingEngine** / **PricingProvider**: exact-key lookup with family fallback;
  live LiteLLM + embedded snapshot.
- **EarningsCalculator**: pure function → per-tool + blended earnings for the
  current billing cycle, plus the daily series.
- **AppModel**: orchestrates; FSEvents triggers incremental rescans, a 60s timer
  refreshes time-based windows.

## Cross-device sync

Sign in (Google or GitHub) and Tokenholic shows a **combined total across all your
devices**. Each device upserts its own small per-device summary to a lightweight
[Supabase](https://supabase.com) backend; Row-Level Security scopes every user to
their own data, and the anon key (the only key shipped) can't read anyone else's.
Every device reads them all and aggregates — the subscription is counted **once**.
Setup: [SUPABASE_SETUP.md](SUPABASE_SETUP.md).

## Releasing

DMGs are built by a GitHub Action (`.github/workflows/build-dmg.yml`) — universal
(Intel + Apple Silicon), Developer-ID-signed + notarized when the signing secrets
are present, ad-hoc otherwise. See [RELEASING.md](RELEASING.md).

## Roadmap

- Cursor support (experimental; dashboard API + session cookie)
- Supabase Realtime for live cross-device updates
- Native Sign in with Apple (requires Developer ID)

## Star history

If Tokenholic earned you something, [give it a ★](https://github.com/conol-ai/tokenholic) —
it's the cheapest way to help other developers find it.

[![Star History Chart](https://api.star-history.com/svg?repos=conol-ai/tokenholic&type=Date)](https://star-history.com/#conol-ai/tokenholic&Date)

## License

Tokenholic is free software, licensed under the **GNU General Public License v3.0**
— see [LICENSE](LICENSE).

Copyright (C) 2026 Tony Huang
