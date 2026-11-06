# Contributing

Thanks for helping out. This is a small project, so the process is light.

## Reporting a bug

Open an issue and include:

- What you expected and what happened
- Your run: deck, stage and blind, and the trinkets you owned
- Your client: Retail or Forever
- Any Lua error text (install a tool such as BugSack if errors are hidden)

## Development setup

There is no build step. The addon is plain Lua.

1. Clone the repo.
2. Symlink `AzerothAnte/` into `World of Warcraft/_forever_/Interface/AddOns/` (or `_retail_`; see the README).
3. Edit, then `/reload` in game to pick up Lua changes. New or changed texture files need a full client restart.

Run the test suites from the repo root before opening a pull request. They need [LuaJIT](https://luajit.org/) and Python 3:

```sh
luajit tests/run.lua          # Core and Data unit tests
luajit tests/smoke_ui.lua     # the real UI against a headless WoW API stub
luajit tests/syntax.lua       # every addon file parses
python3 tests/test_media.py   # generated textures are valid
```

`tools/sim/sim.lua` plays full runs with a bot and reports win rates per deck; run it when a change could shift balance. CI runs [luacheck](https://github.com/lunarmodules/luacheck) on `AzerothAnte/` and every test suite. If you use a new WoW API global, add it to `read_globals` in `.luacheckrc`.

## Code style

- Match the surrounding code: two spaces for indentation, comments only where the reason isn't obvious.
- Every file starts with `local _, ns = ...`. The only globals are `AzerothAnteDB`, `SLASH_AZEROTHANTE1` and `SlashCmdList.AZEROTHANTE`.
- `Core/` and `Data/` never call the WoW API, so they can be tested outside the client.
- All randomness goes through the run's seeded RNG, and chances go through `ns.Prob.roll`.
- Scoring is pure: it works on scratch copies and returns its side effects.
- Run state is plain data. When its shape changes, bump `Save.VERSION` and migrate older saves; never throw them away.
- UI uses the `Theme` helpers and `Tween`. The addon is mouse only.
- New files go in `AzerothAnte.toc`.

## Commits and pull requests

- Use [Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`, `ci:`.
- Keep a pull request to one change.
- Update `CHANGELOG.md` under "Unreleased" and the README if behaviour or commands change.
- Describe what you tested in the client.

## Releasing

Releases are cut by pushing a version tag that matches the `## Version` line in `AzerothAnte/AzerothAnte.toc`, for example `git tag v0.7.0 && git push origin v0.7.0`. For a pre-release tag, the TOC keeps the plain version: `v0.7.0-alpha.1` needs `## Version: 0.7.0`. The Release workflow then:

1. Checks the tag matches the TOC version, and fails if not.
2. Builds `AzerothAnte-<version>-forever.zip`. The `-forever` suffix is how WowUp matches the asset to the Forever client.
3. Publishes a GitHub release with generated notes, and includes `LICENSE` in the zip. A tag with a hyphen (`v0.7.0-alpha.1`) is a pre-release, and goes to CurseForge as alpha (if it says alpha) or beta. Re-running the workflow replaces the asset on an existing release.
4. Uploads the same zip to CurseForge, if configured. Wago is notified by a GitHub webhook on release and reads the game version from the `-forever.zip` name.

The game patch is derived from the Forever interface in the TOC `## Interface` line (`16001` becomes `1.60.1`). CurseForge must already list that Forever patch, or the upload fails.

To enable the CurseForge upload, add these in the repo's Settings > Secrets and variables > Actions. The step is skipped until both are set.

| Secret | Variable |
|--------|----------|
| `CF_API_TOKEN` | `CF_PROJECT_ID` |

Wago needs no secrets here. Link the Wago addon to this repo with a webhook (Settings > Webhooks) that sends release events to `https://addons.wago.io/api/github/webhook`.

## Licence

By contributing you agree your work is released under the [MIT licence](LICENSE).
