#!/usr/bin/env bash
# Формирует build/out/objlist-config.txt и extension-partial-load-*.txt из корневого objlist.txt.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OBJLIST="${ROOT}/objlist.txt"
OUT="${ROOT}/build/out"

if [[ ! -f "$OBJLIST" ]]; then
	echo "Файл objlist.txt не найден: $OBJLIST" >&2
	echo "Скопируйте objlist.txt.example → objlist.txt и заполните путями." >&2
	exit 1
fi

mkdir -p "$OUT"
: > "${OUT}/objlist-config.txt"
rm -f "${OUT}"/extension-partial-load-*.txt "${OUT}"/extension-partial-load-*.txt.tmp

ext_names=()
declare -A EXT_SEEN

while IFS= read -r line || [[ -n "$line" ]]; do
	line="${line#"${line%%[![:space:]]*}"}"
	line="${line%"${line##*[![:space:]]}"}"
	[[ -z "$line" ]] && continue

	if [[ "$line" = /* ]]; then
		full="$line"
	else
		full="${ROOT}/${line}"
	fi

	if [[ "$full" == "${ROOT}/src/cf/"* ]] || [[ "$full" == "${ROOT}/src/cf" ]]; then
		rel="${full#"${ROOT}/src/cf/"}"
		[[ -n "$rel" ]] && echo "$rel" >> "${OUT}/objlist-config.txt"
		continue
	fi

	if [[ "$full" == "${ROOT}/src/cfe/"* ]]; then
		rest="${full#"${ROOT}/src/cfe/"}"
		ext="${rest%%/*}"
		rel="${rest#"$ext"/}"
		if [[ -n "$ext" && -n "$rel" && "$rest" == */* ]]; then
			echo "$rel" >> "${OUT}/extension-partial-load-${ext}.txt.tmp"
			if [[ -z "${EXT_SEEN[$ext]+x}" ]]; then
				EXT_SEEN["$ext"]=1
				ext_names+=("$ext")
			fi
		fi
	fi
done < "$OBJLIST"

if ((${#ext_names[@]} > 0)); then
	for ext in "${ext_names[@]}"; do
		sort -u "${OUT}/extension-partial-load-${ext}.txt.tmp" > "${OUT}/extension-partial-load-${ext}.txt"
		rm -f "${OUT}/extension-partial-load-${ext}.txt.tmp"
	done
fi

cfg_count=$(wc -l < "${OUT}/objlist-config.txt" | tr -d ' ')
echo "objlist-config.txt: ${cfg_count} путей (src/cf)"

if ((${#ext_names[@]} == 0)); then
	echo "Списки расширений: нет путей src/cfe/..."
else
	for ext in "${ext_names[@]}"; do
		cnt=$(wc -l < "${OUT}/extension-partial-load-${ext}.txt" | tr -d ' ')
		echo "extension-partial-load-${ext}.txt: ${cnt} путей"
	done
fi

if [[ "$cfg_count" -eq 0 && ${#ext_names[@]} -eq 0 ]]; then
	echo "В objlist.txt нет путей из src/cf или src/cfe." >&2
	exit 1
fi
