import { useEffect, useState } from "react";

// 検品票 (release manifest) 風ダッシュボード。
// フロントとバックエンドそれぞれのアーティファクト情報を並べ、
// バージョン・git_sha の一致をその場で検品する。
// チュートリアル第3章では staging と production を並べて開き、
// この画面同士が完全一致することを確認する。

type FrontendManifest = {
  service: string;
  version: string;
  git_sha: string;
  built_at: string;
};

type BackendManifest = {
  service: string;
  version: string;
  git_sha: string;
  image_digest: string | null;
  environment: string;
};

function short(sha: string | null | undefined, n = 12) {
  if (!sha) return "—";
  return sha.length > n ? sha.slice(0, n) : sha;
}

// 失敗したとき、どのパスが何を返したのかまで含めて投げる。
//
// fetch は 4xx/5xx では reject しないため、素直に .json() だけ繋ぐと、拾える失敗は
// 「JSON として読めなかった」に潰れる。それだけでは原因を絞れない。
//
// とくに /api の 403 は「200 なのに HTML」として返ってくる。CloudFront の
// custom_error_response (403 -> 200 + /index.html) が SPA ルーティングのために
// ディストリビューション全体へ効いており、API の 403 まで index.html に化けるため
// (terraform/cloudfront.tf)。content-type を見ておかないと、この状況に気付けない。
async function fetchJson<T>(path: string): Promise<T> {
  let res: Response;
  try {
    res = await fetch(path);
  } catch (e) {
    throw new Error(`${path} に接続できません (${e instanceof Error ? e.message : String(e)})`);
  }

  if (!res.ok) {
    throw new Error(`${path} が HTTP ${res.status} ${res.statusText} を返しました`);
  }

  const contentType = res.headers.get("content-type") ?? "";
  if (!contentType.includes("application/json")) {
    throw new Error(
      `${path} が JSON ではなく ${contentType || "不明な形式"} を返しました ` +
        `(CloudFront のエラーページに置き換わっている可能性があります)`,
    );
  }

  return (await res.json()) as T;
}

export default function App() {
  const [fe, setFe] = useState<FrontendManifest | null>(null);
  const [be, setBe] = useState<BackendManifest | null>(null);
  const [errors, setErrors] = useState<string[]>([]);

  useEffect(() => {
    // allSettled で 2 本を独立に扱う。片方だけ落ちたときに、生きている方の
    // 検品結果を捨てずに済み、どちらが落ちたのかも名指しできる。
    Promise.allSettled([
      fetchJson<FrontendManifest>("/version.json"),
      fetchJson<BackendManifest>("/api/version"),
    ]).then(([f, b]) => {
      if (f.status === "fulfilled") setFe(f.value);
      if (b.status === "fulfilled") setBe(b.value);

      setErrors(
        [f, b]
          .filter((r) => r.status === "rejected")
          .map((r) => (r.reason instanceof Error ? r.reason.message : String(r.reason))),
      );
    });
  }, []);

  const loaded = fe !== null && be !== null;
  const versionMatch = loaded && fe.version === be.version;
  const shaMatch = loaded && fe.git_sha === be.git_sha;
  const allMatch = versionMatch && shaMatch;
  const env = be?.environment ?? "…";

  return (
    <main className="slip">
      <header className="slip-head">
        <div>
          <p className="eyebrow">RELEASE MANIFEST — 出荷検品票</p>
          <h1>アーティファクト検品</h1>
        </div>
        <span className={`env env-${env}`}>{env}</span>
      </header>

      {errors.map((message) => (
        <p className="error" key={message}>
          {message}
        </p>
      ))}

      <section className="cards">
        <Artifact
          title="frontend"
          note="GitHub Release アセット (tar.gz + sha256)"
          rows={[
            ["version", fe?.version],
            ["git_sha", short(fe?.git_sha)],
            ["built_at", fe?.built_at],
          ]}
        />
        <Artifact
          title="backend"
          note="ECR コンテナイメージ (digest 参照デプロイ)"
          rows={[
            ["version", be?.version],
            ["git_sha", short(be?.git_sha)],
            ["image_digest", short(be?.image_digest, 26)],
          ]}
        />
      </section>

      <section className="checks">
        <Check label="version 一致" ok={versionMatch} pending={!loaded} />
        <Check label="version 一致" ok={shaMatch} pending={!loaded} />
      </section>

      {loaded && (
        <div className={`stamp ${allMatch ? "stamp-ok" : "stamp-ng"}`} role="status">
          {allMatch ? "検品合格" : "不一致"}
        </div>
      )}

      <footer className="slip-foot">
        <p>
          同一タグの staging / production でこの票が完全一致すれば、
          「build once / deploy many」が守られている証拠です。
        </p>
      </footer>
    </main>
  );
}

function Artifact(props: {
  title: string;
  note: string;
  rows: [string, string | null | undefined][];
}) {
  return (
    <article className="card">
      <h2>{props.title}</h2>
      <p className="note">{props.note}</p>
      <dl>
        {props.rows.map(([k, v]) => (
          <div className="row" key={k}>
            <dt>{k}</dt>
            <dd>{v ?? "…"}</dd>
          </div>
        ))}
      </dl>
    </article>
  );
}

function Check(props: { label: string; ok: boolean; pending: boolean }) {
  const mark = props.pending ? "…" : props.ok ? "✓" : "✗";
  const cls = props.pending ? "" : props.ok ? "ok" : "ng";
  return (
    <p className={`check ${cls}`}>
      <span className="mark">{mark}</span> {props.label}
    </p>
  );
}
