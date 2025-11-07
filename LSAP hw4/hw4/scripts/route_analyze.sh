#!/usr/bin/env bash
set -euo pipefail
D="${1:?usage: route_analyze.sh <domain>}"
OUT_CSV="data/route_${D}.csv"
OUT_MMD="report/route_${D}.mmd"

TR="$(command -v traceroute || true)"
[ -z "$TR" ] && { echo "traceroute not found"; exit 1; }

# 必須先建目錄，否則重導向會失敗
mkdir -p "$(dirname "$OUT_CSV")" "$(dirname "$OUT_MMD")"

echo "hop,ip,hostname,org,country,location,avg_ms" > "$OUT_CSV"

# 只保留「首行含 hop 編號」的輸出（避免續行把 IP 放到 hop 欄）
$TR -n -q 3 -w 2 "$D" \
| awk 'NR>1 && $1 ~ /^[0-9]+$/' \
| while read -r line; do
  hop="$(echo "$line" | awk '{print $1}')"
  ip="$(echo "$line" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)"
  if [ -z "$ip" ]; then
    echo "$line" | grep -q '\* \* \*' && ip="*"
  fi

  if [ "$ip" = "*" ] || [ -z "$ip" ]; then
    hn="*"; org=""; ctry=""; loc=""; avg="-1"
  else
    hn="$(dig +short -x "$ip" | sed 's/\.$//' | head -1)"; [ -z "$hn" ] && hn="-"

    # 用 awk 直接算平均，避免子行程變數遺失
    ms_raw="$(echo "$line" | grep -Eo '[0-9]+(\.[0-9]+)? ms' | awk '{print $1}')"
    avg="$(awk '{s+=$1;n++} END{ if(n>0) printf "%.3f", s/n; else print "-1"}' <<< "$ms_raw")"

    wf="$(whois "$ip" 2>/dev/null || true)"
    org="$(printf "%s\n" "$wf" | awk -F': *' 'tolower($1)~/^(orgname|org-name|owner|organization|descr|netname)$/ {print $2; exit}')"
    ctry="$(printf "%s\n" "$wf" | awk -F': *' 'tolower($1)~/^country$/ {print $2; exit}')"
    [ -z "$org" ] && org="-"; [ -z "$ctry" ] && ctry="-"

    ji="$(curl -m 3 -s "https://ipinfo.io/$ip" || true)"
    city="$(printf "%s" "$ji"   | sed -n 's/.*"city"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'   | head -1)"
    region="$(printf "%s" "$ji" | sed -n 's/.*"region"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
    [ -n "$city$region" ] && loc="$city/$region" || loc="-"
  fi

  # 簡單逃脫雙引號，避免 Mermaid 斷掉
  hn=${hn//\"/\'}; org=${org//\"/\'}; loc=${loc//\"/\'}

  echo "$hop,$ip,$hn,$org,$ctry,$loc,$avg" >> "$OUT_CSV"
done

# 產生 Mermaid 圖：用 process substitution，避免管線子行程
{
  echo "flowchart LR"
  echo "  classDef hop fill:#eef,stroke:#999,rx:10,ry:10;"
  prev=""
  while IFS=, read -r hop ip hn org ctry loc avg; do
    [ "$hop" = "hop" ] && continue
    label="Hop ${hop}\n${ip}\n${hn}\n${org}\n${ctry} ${loc}\n${avg} ms"
    echo "  N${hop}[\"$label\"]:::hop"
    if [ -n "$prev" ]; then
      echo "  N${prev} --> N${hop}"
    fi
    prev="$hop"
  done < <(tail -n +2 "$OUT_CSV")
} > "$OUT_MMD"

echo "Done"
echo "$OUT_CSV"
echo "$OUT_MMD"
