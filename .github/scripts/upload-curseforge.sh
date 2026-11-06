#!/usr/bin/env bash
# Uploads $ZIP to CurseForge as one file for Forever and, where CurseForge knows the
# patch, Retail (the same addon runs on both; the TOC lists both clients' interfaces).
# Needs: CF_API_TOKEN, CF_PROJECT_ID, ZIP, VERSION, STABILITY, PATCH, NOTES_FILE.
# Optional: RETAIL_PATCHES, space-separated (e.g. "12.1.0 12.1.5").
set -euo pipefail

site="https://wow.curseforge.com"
forever_version_type=88568 # CurseForge game version type for WoW Forever

versions=$(curl -fsS -H "x-api-token: $CF_API_TOKEN" "$site/api/game/wow/versions")
version_id=$(jq -r --arg v "$PATCH" --argjson t "$forever_version_type" \
	'map(select(.gameVersionTypeID == $t and .name == $v)) | first | .id // empty' <<<"$versions")
if [ -z "$version_id" ]; then
	echo "CurseForge has no Forever game version $PATCH" >&2
	exit 1
fi

game_versions="[$version_id]"
labels="Forever $PATCH"
# Retail patches are matched by name (12.x names are unique to Retail), skipping Forever's type.
for retail in ${RETAIL_PATCHES:-}; do
	retail_id=$(jq -r --arg v "$retail" --argjson t "$forever_version_type" \
		'map(select(.gameVersionTypeID != $t and .name == $v)) | first | .id // empty' <<<"$versions")
	if [ -z "$retail_id" ]; then
		echo "warning: CurseForge has no Retail game version $retail; skipping it" >&2
		continue
	fi
	game_versions=$(jq -c --argjson id "$retail_id" '. + [$id]' <<<"$game_versions")
	labels="$labels, Retail $retail"
done

metadata=$(jq -n \
	--arg name "$VERSION" \
	--arg release "$STABILITY" \
	--argjson gameVersions "$game_versions" \
	--rawfile changelog "$NOTES_FILE" \
	'{displayName: $name, releaseType: $release, gameVersions: $gameVersions, changelogType: "markdown", changelog: $changelog}')

echo "Uploading $ZIP to CurseForge project $CF_PROJECT_ID ($labels, $STABILITY)"
curl -fsS -H "x-api-token: $CF_API_TOKEN" \
	-F "metadata=$metadata" -F "file=@$ZIP" \
	"$site/api/projects/$CF_PROJECT_ID/upload-file"
echo
