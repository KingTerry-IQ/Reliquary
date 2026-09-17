# Reliquary

**Search the archive. Inscribe a title. Play what the chain already holds.**

A GodOnChain guest, in the same shape as Burning Bush Protocol: no keys, no sidecar, no GDExtension. Copy of `addons/iq_client` talks to whatever GodOnChain launched you. Ruffle is downloaded as the latest stable desktop build and launched as its own window.

Each inscribed Flash GameZIP is **its own IQDB table** under

```
GodOnChain-KingTerry-FlashCartridge
```

That path was kindled before the name Reliquary. It does not move.

The dbRoot is already kindled on MON, SOL, and RH. Inscribe is refused if that sentinel is missing.

## Using it

1. Open the project in Godot 4.7+ and press F5, or launch the exported PCK from GodOnChain.
2. SEARCH the Flashpoint catalog (Flash GameZIPs only).
3. INSCRIBE a title. The app quotes the cost and asks you to confirm: this game stays permanently accessible. GodOnChain then asks you to approve createTable and two rows.
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
  cabinet.gd        list, inscribe, read
  flashpoint.gd     search + GameZIP download
  ruffle.gd         latest stable from GitHub
  costs.gd          quotes
  unzip.gd          GameZIP → SWF
  shelf.gd          local cache index
  temple_theme.gd   sixteen colours on black
tools/selftest.gd
```
