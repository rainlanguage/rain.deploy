# Pass 0: Process Review — 2026-03-05-02

## Documents Reviewed
- `CLAUDE.md`
- `foundry.toml`
- `slither.config.json`
- `.github/workflows/rainix.yaml`

## Findings

### A01-1 [LOW] CI missing FLARE_RPC_URL and POLYGON_RPC_URL env vars

**Location:** `.github/workflows/rainix.yaml`, lines 56-57

The workflow passes `ARBITRUM_RPC_URL` and `BASE_RPC_URL` to the test step but omits `FLARE_RPC_URL` and `POLYGON_RPC_URL`. These are defined in `foundry.toml` (lines 14-15) and documented in `CLAUDE.md` (lines 44-45). Any future test that forks Flare or Polygon will fail in CI silently.

### A01-2 [LOW] CLAUDE.md RPC section has placeholder values for Flare and Polygon

**Location:** `CLAUDE.md`, lines 44-45

The RPC configuration section provides real URLs for Arbitrum and Base but uses `<flare rpc url>` and `<polygon rpc url>` placeholders for Flare and Polygon. A future session copying these values verbatim into `.env` would get invalid URLs. Either provide real public RPC URLs or explicitly state these must be filled in by the developer.
