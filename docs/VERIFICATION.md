# Initial verification — 2026-11-14

Environment: Linux x86_64, Godot 4.7.2.stable.official.ed1daf0bf, Google Chrome via Playwright, Compatibility renderer.

Completed locally:

- Headless import and single-threaded Web release export using matching official templates. Export log had no errors/warnings. Output contains HTML, JS, PCK and WASM (about 39 MB uncompressed).
- `tests/test_world.gd`: `WORLD_TESTS_PASS`. Checks name/session authentication, nonfinite movement rejection, server speed limit, gathering distance/cooldown, depletion/respawn, crafting inputs/output, escrow, save/reload, negative prices, purchase replay rejection, exact coin/item transfers, disconnect/restart refunds, credential exclusion, spear damage, drone loot/respawn, death rescue and resource persistence.
- Dedicated headless Godot server plus two independent headless clients: both printed `NETWORK_SMOKE_PASS`, gathered wood and reported two peers.
- Two isolated Chrome browser contexts loaded the actual exported WASM client over HTTP, joined the same WebSocket server using distinct accounts, received live snapshots, and exercised keyboard movement. The test checked both saved accounts and changed authoritative position, with no browser console/page errors. `BROWSER_SMOKE_PASS` reported 822 received frames in the first run.
- Browser screenshot visually inspected: world, two players, HUD, inventory and recipe controls render correctly. `docs/browser-gameplay.png` is from that shared browser session.
- Git whitespace check passed.

The rules test simulates transactions and combat directly; those checks are not a claim of a complete human multiplayer combat playtest. Secure reverse-proxy Internet hosting, mobile/Safari/Firefox behavior, reconnect under packet loss, sudden power loss, large-population performance and anti-abuse hardening have not been verified. CI is configured to repeat the rules tests and export on GitHub; local results above do not imply a hosted CI result.
