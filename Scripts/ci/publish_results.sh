#!/usr/bin/env bash
# Legt Build-Log, Fehlerauszug und Screenshots eines CI-Laufs auf einem eigenen
# Branch ab (`ci-<art>`, z. B. `ci-ios`). Der Branch enthält immer nur den letzten
# Lauf (ein einzelner Commit, wird überschrieben), damit das Repo klein bleibt.
#
# So lassen sich Ergebnisse per `git fetch origin ci-ios` abholen, auch ohne
# API-Token für Artefakte.
#
# Aufruf: Scripts/ci/publish_results.sh <art> <job-status>
# Braucht: GITHUB_TOKEN, GITHUB_REPOSITORY, GITHUB_SHA, GITHUB_RUN_ID
set -euo pipefail

KIND="$1"
STATUS="${2:-unknown}"
BRANCH="ci-${KIND}"
WORK="$(mktemp -d)"
REMOTE="https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"

mkdir -p "$WORK/results"

# Screenshots (falls vorhanden)
if [[ -d build/screenshots ]]; then
  find build/screenshots -maxdepth 1 -name "*.png" -exec cp {} "$WORK/results/" \;
fi

# Logs komprimiert, plus lesbarer Fehlerauszug
for log in build/xcodebuild.log build/archive.log; do
  if [[ -f "$log" ]]; then
    name="$(basename "$log")"
    gzip -c "$log" > "$WORK/results/${name}.gz"
    grep -nE "error:|warning: .*(/App/|/Widgets/|/UITests/|/Packages/)|\*\* (BUILD|TEST|ARCHIVE) (SUCCEEDED|FAILED) \*\*|Test Case .*(passed|failed)|Testing failed|Fatal error" "$log" \
      | head -400 > "$WORK/results/${name%.log}-auszug.txt" || true
  fi
done

# Berechtigungen der signierten App (nur Release)
if [[ -f build/entitlements.txt ]]; then
  cp build/entitlements.txt "$WORK/results/"
fi

cat > "$WORK/results/RUN.md" <<EOF
# CI-Ergebnis: ${KIND}

- Status: ${STATUS}
- Commit: ${GITHUB_SHA}
- Lauf: https://github.com/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}
- Zeit (UTC): $(date -u +"%Y-%m-%d %H:%M")
EOF

cd "$WORK"
git init -q
git checkout -q --orphan "$BRANCH"
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add -A
git commit -q -m "CI-Ergebnis ${KIND}: ${STATUS} (${GITHUB_SHA:0:7}, Lauf ${GITHUB_RUN_ID})"
git push -q --force "$REMOTE" "HEAD:refs/heads/${BRANCH}"
echo "Ergebnisse auf Branch ${BRANCH} veröffentlicht."
