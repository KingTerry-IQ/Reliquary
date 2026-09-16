## Protocol-fee estimates for inscribing a cartridge.
##
## Mirrors GodOnChain's approval quotes. Reads are free. Gas is excluded.
## The number shown before the user says yes has to be the same shape as
## the number the host will show.

class_name Costs
extends RefCounted

const SOL_BASE := 0.005105
const SOL_PER_CHUNK := 0.000005
const SOL_CHUNK_BYTES := 850

const MON_BASIC_FEE := 6.5
const MON_LINKED_FEE := 19.5
const MON_CREATE_TABLE := 19.5
const MON_INLINE_LIMIT := 700
const MON_CHUNK_BYTES := 70656
const MON_PER_CHUNK := 0.415972

const RH_BASIC_FEE := 0.00012
const RH_LINKED_FEE := 0.00036
const RH_CREATE_TABLE := 0.00036
const RH_INLINE_LIMIT := 700
const RH_CHUNK_BYTES := 98_304


static func is_monad(chain: String) -> bool:
	var c := chain.strip_edges().to_lower()
	return c == "mon" or c == "monad"


static func is_robinhood(chain: String) -> bool:
	var c := chain.strip_edges().to_lower()
	return c == "rh" or c == "rhc" or c == "robinhood" or c == "robinhood-chain"


static func token(chain: String) -> String:
	if is_robinhood(chain):
		return "ETH"
	if is_monad(chain):
		return "MON"
	return "SOL"


static func create_table(chain: String) -> float:
	if is_robinhood(chain):
		return RH_CREATE_TABLE
	return MON_CREATE_TABLE if is_monad(chain) else SOL_BASE


static func write_row(chain: String, bytes: int = 64) -> float:
	if is_robinhood(chain):
		return RH_LINKED_FEE if bytes > RH_INLINE_LIMIT else RH_BASIC_FEE
	if is_monad(chain):
		if bytes <= MON_INLINE_LIMIT:
			return MON_BASIC_FEE
		@warning_ignore("integer_division")
		var mon_chunks: int = (bytes + MON_CHUNK_BYTES - 1) / MON_CHUNK_BYTES
		return MON_LINKED_FEE + maxi(mon_chunks - 1, 0) * MON_PER_CHUNK
	@warning_ignore("integer_division")
	var sol_chunks: int = (maxi(bytes, 1) + SOL_CHUNK_BYTES - 1) / SOL_CHUNK_BYTES
	return SOL_BASE + sol_chunks * SOL_PER_CHUNK


## On-chain size of a binary after base64. That is what the chain is billed for.
static func base64_bytes(raw: int) -> int:
	return ((maxi(raw, 0) + 2) / 3) * 4


## createTable + meta row + blob row for a zip of this many original bytes.
static func inscribe(chain: String, raw_zip_bytes: int) -> float:
	var blob := base64_bytes(raw_zip_bytes)
	return create_table(chain) + write_row(chain, 256) + write_row(chain, blob)


static func format(chain: String, amount: float) -> String:
	if is_robinhood(chain):
		return "%.5f ETH" % amount
	if is_monad(chain):
		return "%.1f MON" % amount
	return "%.4f SOL" % amount


static func quote_inscribe(chain: String, raw_zip_bytes: int) -> String:
	return (
		"About %s to inscribe (%s createTable to the root, the rest for the rows)."
		% [format(chain, inscribe(chain, raw_zip_bytes)), format(chain, create_table(chain))]
	)
