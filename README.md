# Reliquary

**Search the archive. Inscribe a title. Play what the chain already holds.**

A GodOnChain guest, in the same shape as Burning Bush Protocol: no keys, no sidecar, no GDExtension. Copy of `addons/iq_client` talks to whatever GodOnChain launched you. Players are downloaded on demand and launched as their own window.

Flash entries play the way Flashpoint plays them: in the standalone projector their `applicationPath` names, fetched from Flashpoint's own `supportpack-flash`. Those projectors are import-patched to load `FlashpointProxy`, which reads `port.txt` beside the exe and points that process at our loopback server — so the movie keeps its archived `http://host/path` URL and every relative and absolute load lands back in the cartridge. Ruffle is the fallback, the same way it is for Flashpoint. The **FLASH** chip in the top bar flips which one leads.

Entries whose `applicationPath` names a browser are pages, and Flashpoint opens
pages in its own Navigator — plugin-in-page Flash and HTML5 alike. We follow it
there, fetching Navigator on first use. The **NAV** chip hands them to this
machine's browser instead: a newer engine, but not the one the archive was
curated against. Entries that need a real plugin ignore the toggle, because for
those there is no browser to fall back to.

Each inscribed Flash GameZIP is **its own IQDB table** under

```
GodOnChain-KingTerry-FlashCartridge
```

That path was kindled before the name Reliquary. It does not move.

The dbRoot is already kindled on MON, SOL, and RH. Inscribe is refused if that sentinel is missing.

## Favourites

**★ FAVOURITE** on the stage keeps a local bookmark to a title, and **★
Favourites** in the playlist dropdown lists them, newest mark first. A star
marks them in the archive list too, so you can see what you have kept while
browsing everything.

A favourite costs nothing and writes nothing to the chain — it is not an
inscription. The catalog row is saved with it in `user://favorites.json`, so
the collection opens with no network and no catalog; when the archive *is*
reachable, the live row wins and the saved copy is only the fallback.

## Tag filters

The **SAFE** chip carries Flashpoint's own tag filters, read from the same
`core-configuration` component its launcher reads, with a built-in copy so the
filter works offline. Seven groups; five marked *extreme*, hidden while SHOW
EXTREME is off — which is how Flashpoint ships. Out of the box that hides 4,905
of 32,506 animations and 8,031 of 180,016 games.

This filters what the ARCHIVE pane lists. It does not gate inscribe, and it
never hides a cartridge you already own from the CABINET. The tags are
crowd-curated, so it is a strong filter, not a guarantee.

## Using it

1. Open the project in Godot 4.7+ and press F5, or launch the exported PCK from GodOnChain.
2. SEARCH the Flashpoint catalog (Flash GameZIPs only).
3. INSCRIBE a title. The app quotes the cost and asks you to confirm: this game stays permanently accessible. GodOnChain then asks you to approve createTable and two rows.
4. PLAY an inscribed title. The zip is read from the chain (or the local cache) and handed to Ruffle.

Without a host the archive still searches and cached cartridges still play. Writes do not.

```bash
Godot --headless --path . --script res://tools/selftest.gd
```

## Soak testing

Launch real titles one at a time and record whether each actually starts,
deleting every download as it goes so the disk never fills.

```bash
Godot --headless --path . --script res://tools/soak.gd -- --limit 25
Godot --headless --path . --script res://tools/soak.gd -- --ids <uuid>,<uuid>
```

`--platform`, `--library`, `--query`, `--seed`, `--dwell`, `--out`, `--keep`,
and `--extreme` (which drops the tag filters the app applies by default).

**STARTED** means the player fetched the launch file from us, is still running,
has a visible window, and nothing 404'd. **DEGRADED** is all of that with assets
missing. **ERROR-PAGE** is a window showing the runtime's own load failure,
**NO-WINDOW** never opened one, **NO-FETCH** never asked for the movie,
**EXITED** asked and then quit, and **STUCK** means a previous title's player
would not close, so this one never got a fair run.

None of this proves a game is *playable* — only a human or a pixel check can say
that. It proves the launch path worked end to end, which is the part we can get
wrong.

## Layout

```
addons/iq_client/   drop-in GodOnChain client
Scenes/main.gd      the app
Scripts/
  cartridge.gd      table names, rows, hashes
  cabinet.gd        list, inscribe, read
  flashpoint.gd     search + GameZIP download
  favorites.gd      local bookmarks + the collection
  flash.gd          Flashpoint's own Flash projectors
  tag_filter.gd     Flashpoint's tag filters
  ruffle.gd         latest stable from GitHub
  costs.gd          quotes
  unzip.gd          GameZIP → SWF
  shelf.gd          local cache index
  temple_theme.gd   sixteen colours on black
tools/
  selftest.gd       headless checks
  soak.gd           launch real titles, one at a time
```
