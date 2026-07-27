// ビルド時にフロントエンドのバージョン情報を public/version.json として生成する。
// コンテナの ARG 焼き込みに対応する、静的アーティファクト側の仕組み。
// RC ビルドでも "-rc.N" を除いた基底バージョンが渡ってくる。
import { mkdirSync, writeFileSync } from "node:fs";

const manifest = {
  service: "frontend",
  version: process.env.APP_VERSION ?? "local",
  git_sha: process.env.GIT_SHA ?? "local",
  built_at: new Date().toISOString(),
};

mkdirSync("public", { recursive: true });
writeFileSync("public/version.json", JSON.stringify(manifest, null, 2) + "\n");
console.log("generated public/version.json:", manifest);
