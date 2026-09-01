# Token Fish

What if the tokens you spend with coding agents also fed a living aquarium on
your Omarchy wallpaper? Code more and the fish eat, grow, breed, overcrowd,
and eventually become sushi, served the
[omakase way](https://learn.omacom.io/3/omacom/76/omakase-computing).

**Token Fish** is a living aquarium that floats over your Omarchy wallpaper,
**fed by your AI coding token usage**. The more tokens you use, the more fish
grow, and the more sushi you'll have.

## Demo

https://github.com/user-attachments/assets/9af060bc-d69e-4622-ae69-c0df3a4faf8e

## Install

```sh
omarchy plugin add https://github.com/closetheloop-dev/token-fish --enable
```

To turn it off without uninstalling, disable it; to remove it entirely:

```sh
omarchy plugin disable io.github.closetheloop-dev.token-fish
omarchy plugin remove io.github.closetheloop-dev.token-fish
```

## Feeding: tokens are food

The fish eat the tokens you spend with your AI coding agents. A background reader
(`FoodSource.qml`) watches the usage records the `omarchy.agents` collectors write:

- It reads `~/.local/state/omarchy/agents/usage/*.json` (Claude Code, Codex,
  Fireworks, …) to get summarized token totals computed by the command
  `omarchy-agent-usage-<agent>`.
- For each agent it tracks the cumulative `input + output` token count and remembers
  the last value it saw. Whenever that number goes **up** (you used more tokens), the
  difference is turned into food: about **one pellet per 400 tokens** (1–12
  pellets per burst).
- On startup it just records where each counter is, without feeding, so launching
  the plugin doesn't dump your whole history as one giant meal.
- It refreshes the usage numbers itself every couple of minutes.

Feeding drops **falling food flakes** and, if the tank isn't crowded, spawns up to
**2 new fish** near the well-fed ones (up to a configurable maximum). You can also
feed by hand with the **Feed** button in the panel.

## Fish → sushi

A few times a minute, the tank checks how crowded it is. Any fish with too many
nearby neighbours (default limit: 3) has a chance of becoming sushi. When chosen,
it transforms into a piece of sushi and fades away. A running 🍣 counter keeps
score of how many have been eaten.

## The loop

**code → tokens spent → food rains down → well-fed fish breed → the tank fills up →
overcrowding → fish become sushi → room frees up → code …**

A tiny token-fed ecology on your desktop: the more (and harder) you code, the busier
(and more crowded, and more sushi-prone) your aquarium gets.

## Controls & structure

A clownfish icon in the bar opens a panel to tune the tank: population and crowding
limits, whether food is shown, swim speed, a **Freeze** switch and frame-rate cap
(handy on software rendering), a manual **Feed** button, and a toggle for the small
🐟 / 🍣 counter shown in the corner of the wallpaper. Settings persist to
`~/.local/state/io.github.closetheloop-dev.token-fish/settings.json`.

Under the hood it's two parts: a `service` that renders the aquarium as a
click-through overlay on each monitor's wallpaper layer, and a `bar-widget` for the
controls panel.

## Requirements and token source

Token Fish does not inspect your agents' raw session files or count tokens itself.
It relies on Omarchy's agent-usage collectors:

```text
$OMARCHY_PATH/bin/omarchy-agent-usage-<agent>
                    ↓
        omarchy-agent-usage-update
                    ↓
~/.local/state/omarchy/agents/usage/<agent>.json
                    ↓
               Token Fish
```

The updater discovers executable collectors named
`omarchy-agent-usage-<agent>` and writes one summarized JSON record per agent.
Token Fish runs the updater every couple of minutes and watches those records, so
the Agents bar widget does not need to be enabled.

Before relying on automatic feeding, replace `<agent>` with your agent id (for
example `claude`, `codex`, or `fireworks`) and check that:

```bash
test -x "$OMARCHY_PATH/bin/omarchy-agent-usage-<agent>"
jq . "${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/agents/usage/<agent>.json"
```

`$OMARCHY_PATH` is set automatically in an Omarchy desktop session. In an SSH
session, export it first: `export OMARCHY_PATH=/usr/share/omarchy`. The updater
needs it to find collectors.

The JSON should exist, be valid, and contain totals for your machine that update
after you use the agent. If the collector or record is missing, install that
agent's Omarchy usage collector first. Not every agent ships one yet. For
example, OpenCode Go support is proposed in
[omacom/omarchy#6779](https://github.com/omacom/omarchy/pull/6779), but is not
currently shipped by Omarchy, so automatic OpenCode Go feeding requires
installing a compatible collector separately.

If your agent has no collector, you can write one or have an agent write it for
you, following the `omarchy-agent-usage-<agent>` contract: an executable of
that name in `$OMARCHY_PATH/bin` that prints one JSON usage record to stdout
(exactly what `omarchy-agent-usage-update` runs and reads). Manual feeding
still works without any collector.

## Credits

Artwork is available under [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)
(public domain), from [freesvg.org](https://freesvg.org/):

- [Fish](https://freesvg.org/fish-cartoon)
- [Sushi](https://freesvg.org/1501706222)

## License

Token Fish is released under the [MIT License](LICENSE). The bundled fish and
sushi artwork is available under CC0 1.0, as noted above.
