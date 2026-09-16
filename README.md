# Flash Cartridge

**Search the archive. Inscribe a title. Play what the chain already holds.**

A GodOnChain guest, in the same shape as Burning Bush Protocol: no keys, no sidecar, no GDExtension. Copy of `addons/iq_client` talks to whatever GodOnChain launched you. Ruffle is downloaded as the latest stable desktop build and launched as its own window.

Each inscribed Flash GameZIP is **its own IQDB table** under

```
GodOnChain-KingTerry-FlashCartridge
```

`createTable` pays the root creator — the operators — not the person who clicked Inscribe.

## Kindling (operators, once per chain)

The sidecar will initialize a missing dbRoot as whoever first calls `createTable`. If a stranger does that, they own the fee stream forever.

From the funded GodOnChain wallet that should receive those fees:

1. Launch this app (or run it next to GodOnChain).
2. Pick the chain (default **MON**).
3. **KINDLE ROOT**. That creates the sentinel table `kindled` and stamps you as creator.

The app refuses Inscribe until `kindled` exists.

Do this on each chain you intend to support. A Monad root is not a Solana root.

## Using it

1. Open the project in Godot 4.7+ and press F5, or launch the exported PCK from GodOnChain.
2. SEARCH the Flashpoint catalog (Flash GameZIPs only).
3. INSCRIBE a title. GodOnChain will ask you to approve createTable, then two rows. There is no unpublish.
4. PLAY an inscribed title. The zip is read from the chain (or the local cache) and handed to Ruffle.

Without a host the archive still searches and cached cartridges still play. Writes do not.

```bash
Godot --headless --path . --script res://tools/selftest.gd
```

## Layout

```
addons/iq_client/   drop-in GodOnChain client
Scenes/main.gd      the app
Scripts/
  cartridge.gd      table names, rows, hashes
  cabinet.gd        kindle, list, inscribe, read
  flashpoint.gd     search + GameZIP download
  ruffle.gd         latest stable from GitHub
  costs.gd          quotes
  unzip.gd          GameZIP → SWF
  shelf.gd          local cache index
  temple_theme.gd   sixteen colours on black
tools/selftest.gd
```
