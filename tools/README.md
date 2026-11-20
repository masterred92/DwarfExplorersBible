# tools

- `fetch_hotfixes.py <build> <Table> <out.json> [ids]` - wago.tools' public hotfix list for one table (product wowf).
- `gen_data.py <csv dir> --build <full build> [--hotfixes <dir>] [--hotfix-build <n>] [--vendor data.json]` - writes Data.lua.
- `verify_api.py <wow-ui-source checkout> *.lua` - checks every API, event, template and font object we use exists in
  Blizzard's Forever UI source (run by `tests/run.sh <path>`). `host_api.py` lists client globals that aren't in it.

## Inputs each release was built from

| Release | Client build | Kept at |
|---|---|---|
| 1.2.0 | 1.60.1.71037 (tables) + 70959 hotfixes | `/workspace/wow-research/raw/deb-db2/1.60.1.71037/` (CSV exports, hotfix JSON, SHA256SUMS, rebuild command in its README.md) |
| 1.2.0 (first build, d939aec) | 1.60.1.70959 tables | `/workspace/wow-research/raw/deb-db2/1.60.1.70959/` (same 10 tables, byte-identical to 71037's; `cmp` command in its README.md) |

Rebuild 1.2.0's Data.lua:

    D=/workspace/wow-research/raw/deb-db2/1.60.1.71037
    tools/gen_data.py $D/csv --build 1.60.1.71037 --hotfixes $D/hotfixes-70959 --hotfix-build 70959 \
      --vendor /workspace/wow-addons/data/nexus-data.json --out Data.lua
