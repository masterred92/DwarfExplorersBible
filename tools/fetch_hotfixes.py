#!/usr/bin/env python3
"""Downloads WoW: Forever server hotfix rows for one DB2 table from wago.tools' public hotfix list.
Usage: tools/fetch_hotfixes.py <build> <table> <out.json> [record id ...]
With record ids, only those records are fetched (one search each); otherwise every page of the table.
Writes a JSON list of the raw rows (push_id, record_id, status, build, table_name, data, locale, ...)."""
import html, json, re, sys, time, urllib.parse, urllib.request

BASE = "https://wago.tools/hotfixes"
UA = {"User-Agent": "DwarfExplorersBible-gen_data (github.com/masterred92/DwarfExplorersBible)"}
_version = None


def get(search, page):
    global _version
    url = BASE + "?" + urllib.parse.urlencode({"product": "wowf", "search": search, "page": page})
    hdr = dict(UA)
    if _version:
        hdr.update({"X-Inertia": "true", "X-Inertia-Version": _version, "X-Requested-With": "XMLHttpRequest"})
    for attempt in range(5):
        try:
            body = urllib.request.urlopen(urllib.request.Request(url, headers=hdr), timeout=90).read().decode("utf-8")
            break
        except Exception as e:  # network hiccup or rate limit: back off and retry
            if attempt == 4: raise
            time.sleep(5 * (attempt + 1))
    if body.lstrip().startswith("{"):
        page_obj = json.loads(body)
    else:  # first request: the HTML page embeds the same JSON in data-page
        page_obj = json.loads(html.unescape(re.search(r'data-page="([^"]*)"', body).group(1)))
        _version = page_obj.get("version")
    return page_obj["props"]["hotfixes"]


def fetch(search):
    rows, page = [], 1
    while True:
        h = get(search, page)
        rows += h["data"]
        if page >= h["last_page"]: return rows
        page += 1
        time.sleep(0.5)


def main():
    build, table, out = sys.argv[1], sys.argv[2].lower(), sys.argv[3]
    ids = sys.argv[4:]
    rows = []
    if ids:
        for rid in ids:
            # search_text is "<locale> <push> <record> <build> <table> [data]", so this phrase pins one record.
            rows += [r for r in fetch(f"{rid} {build} {table}") if str(r["record_id"]) == rid]
    else:
        rows = fetch(f"{build} {table}")
    rows = [r for r in rows if str(r.get("build")) == build and r.get("table_name", "").lower() == table]
    json.dump(rows, open(out, "w", encoding="utf-8"))
    print(len(rows), "rows,", len({r["record_id"] for r in rows}), "records ->", out)


if __name__ == "__main__":
    main()
