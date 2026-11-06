#!/usr/bin/env bash
# Uploads $ZIP to CurseForge as a Forever file.
# Needs: CF_API_TOKEN, CF_PROJECT_ID, ZIP, VERSION, STABILITY, PATCH, NOTES_FILE.
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

metadata=$(jq -n \
	--arg name "$VERSION" \
	--arg release "$STABILITY" \
	--argjson gameVersion "$version_id" \
	--rawfile changelog "$NOTES_FILE" \
	'{displayName: $name, releaseType: $release, gameVersions: [$gameVersion], changelogType: "markdown", changelog: $changelog}')

echo "Uploading $ZIP to CurseForge project $CF_PROJECT_ID (Forever $PATCH, $STABILITY)"
curl -fsS -H "x-api-token: $CF_API_TOKEN" \
	-F "metadata=$metadata" -F "file=@$ZIP" \
	"$site/api/projects/$CF_PROJECT_ID/upload-file"
echo
