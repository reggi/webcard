import assert from "node:assert/strict";
import { test } from "node:test";
import { loadRelease, releaseMetadata } from "./release-metadata.mjs";

function fixture(tag = "v0.2.0") {
  const name = `Webcard-${tag.slice(1)}-macOS-universal.zip`;
  return {
    tag_name: tag,
    draft: false,
    prerelease: false,
    assets: [name, `${name}.sha256`].map((assetName) => ({
      name: assetName,
      state: "uploaded",
      size: 100,
      browser_download_url: `https://github.com/reggi/webcard/releases/download/${tag}/${assetName}`,
    })),
  };
}

test("generates download links for the exact published release", () => {
  const result = releaseMetadata(fixture("v1.2.3"));
  assert.equal(result.version, "1.2.3");
  assert.equal(
    result.downloadUrl,
    "https://github.com/reggi/webcard/releases/download/v1.2.3/Webcard-1.2.3-macOS-universal.zip",
  );
  assert.equal(result.checksumUrl, `${result.downloadUrl}.sha256`);
  assert.equal(
    result.releaseUrl,
    "https://github.com/reggi/webcard/releases/tag/v1.2.3",
  );
});

test("rejects missing releases, drafts, and prereleases", () => {
  for (const release of [
    null,
    {},
    { ...fixture(), draft: true },
    { ...fixture(), prerelease: true },
    fixture("v1.0.0-beta.1"),
  ]) {
    assert.throws(() => releaseMetadata(release));
  }
});

test("fails rather than publishing broken or unexpected download links", () => {
  for (const assets of [
    [],
    [fixture().assets[0]],
    fixture().assets.map((asset) => ({ ...asset, size: 0 })),
    fixture().assets.map((asset) => ({ ...asset, state: "new" })),
    fixture().assets.map((asset) => ({
      ...asset,
      browser_download_url: "https://example.invalid/download",
    })),
  ]) {
    assert.throws(() => releaseMetadata({ ...fixture(), assets }));
  }
});

test("rejects invalid tag input before contacting GitHub", async () => {
  await assert.rejects(loadRelease("main"), /RELEASE_TAG/);
});

test("reports API failures and refuses a mismatched release", async (t) => {
  t.mock.method(
    globalThis,
    "fetch",
    async () => new Response("", { status: 404 }),
  );
  await assert.rejects(loadRelease("v0.2.0"), /HTTP 404/);

  globalThis.fetch.mock.mockImplementation(async () =>
    Response.json(fixture("v0.1.0")),
  );
  await assert.rejects(loadRelease("v0.2.0"), /different release/);
});
