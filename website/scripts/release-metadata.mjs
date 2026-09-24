import { writeFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";

const repository = "https://github.com/reggi/webcard";

export function releaseMetadata(release) {
  if (
    !release ||
    release.draft ||
    release.prerelease ||
    !/^v\d+\.\d+\.\d+$/.test(release.tag_name)
  ) {
    throw new Error("A published stable Webcard release is required.");
  }

  const tag = release.tag_name;
  const version = tag.slice(1);
  const archiveName = `Webcard-${version}-macOS-universal.zip`;
  const assetUrl = (name) => {
    const asset = release.assets?.find((entry) => entry.name === name);
    const expected = `${repository}/releases/download/${tag}/${name}`;
    if (
      !asset ||
      asset.state !== "uploaded" ||
      asset.size <= 0 ||
      asset.browser_download_url !== expected
    ) {
      throw new Error(`The release is missing a completed asset: ${name}`);
    }
    return expected;
  };

  return {
    version,
    tag,
    releaseUrl: `${repository}/releases/tag/${tag}`,
    downloadUrl: assetUrl(archiveName),
    checksumUrl: assetUrl(`${archiveName}.sha256`),
  };
}

export async function loadRelease(tag = "", token = "") {
  if (tag && !/^v\d+\.\d+\.\d+$/.test(tag)) {
    throw new Error("RELEASE_TAG must be a stable version tag such as v0.2.0.");
  }

  const endpoint = tag ? `tags/${encodeURIComponent(tag)}` : "latest";
  const headers = {
    Accept: "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
  };
  if (token) headers.Authorization = `Bearer ${token}`;

  const response = await fetch(
    `https://api.github.com/repos/reggi/webcard/releases/${endpoint}`,
    {
      headers,
      signal: AbortSignal.timeout(15_000),
    },
  );
  if (!response.ok) {
    throw new Error(`GitHub release lookup failed (HTTP ${response.status}).`);
  }

  const release = await response.json();
  if (tag && release.tag_name !== tag) {
    throw new Error("GitHub returned a different release than requested.");
  }
  return releaseMetadata(release);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const release = await loadRelease(
      process.env.RELEASE_TAG,
      process.env.GH_TOKEN,
    );
    await writeFile(
      new URL("../src/release.generated.json", import.meta.url),
      `${JSON.stringify(release, null, 2)}\n`,
    );
    console.log(`Building the Webcard website for ${release.tag}.`);
  } catch (error) {
    console.error(
      error instanceof Error
        ? error.message
        : "Could not load release metadata.",
    );
    process.exitCode = 1;
  }
}
