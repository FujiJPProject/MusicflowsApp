import { useState, type FormEvent } from "react";
import { Link } from "react-router-dom";
import { TestsApi, type Tests } from "../../api/dev/testsApi";
import { signIn, type AuthSession } from "../../auth/cognitoAuth";
import { getPkceSession } from "../../auth/cognitoPkce";
import type { RuntimeConfig } from "../../config/runtimeConfig";

export default function DatabaseTestPage({ config }: { config: RuntimeConfig }) {
  const [mode, setMode] = useState<"direct" | "lambda">(config.directApiBaseUrl ? "direct" : "lambda");
  const [session, setSession] = useState<AuthSession | null>(() => getPkceSession());
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [name, setName] = useState("");
  const [rows, setRows] = useState<Tests[]>([]);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const baseUrl = mode === "direct" ? config.directApiBaseUrl : config.apiBaseUrl;
  const api = baseUrl && (mode === "direct" || session)
    ? new TestsApi(baseUrl, mode === "lambda" ? session?.accessToken : undefined)
    : null;

  async function execute(action: () => Promise<void>) {
    setBusy(true); setError("");
    try { await action(); }
    catch (cause) { setError(cause instanceof Error ? cause.message : String(cause)); }
    finally { setBusy(false); }
  }

  function login(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    void execute(async () => {
      try { setSession(await signIn(config, username, password)); }
      finally { setPassword(""); }
    });
  }

  return <main>
    <h1>DB疎通確認</h1>
    <p><Link to="/">トップへ戻る</Link> / <Link to="/auth-test">認証確認</Link> / <Link to="/jobtest">ジョブ確認</Link></p>
    <label>接続経路
      <select value={mode} disabled={busy} onChange={(event) => {
        setMode(event.target.value === "direct" ? "direct" : "lambda");
        setRows([]); setError("");
      }}>
        {config.directApiBaseUrl && <option value="direct">Spring Boot直接</option>}
        <option value="lambda">API Gateway / Lambda</option>
      </select>
    </label>
    <p>接続先: {baseUrl}</p>
    {mode === "lambda" && !session && (config.deploymentStage === "local" ? (
      <form onSubmit={login}>
        <input aria-label="ユーザー名" value={username} autoComplete="username" required onChange={(e) => setUsername(e.target.value)} />
        <input aria-label="パスワード" type="password" value={password} autoComplete="current-password" required onChange={(e) => setPassword(e.target.value)} />
        <button disabled={busy}>Cognitoログイン</button>
      </form>
    ) : <p><Link to="/auth-test">Cognito OAuth認証を実施</Link></p>)}
    <form onSubmit={(event) => {
      event.preventDefault();
      if (api && name.trim()) void execute(async () => {
        await api.createTest({ name: name.trim() });
        setRows(await api.getTests()); setName("");
      });
    }}>
      <input aria-label="プロジェクト名" value={name} maxLength={100} required onChange={(e) => setName(e.target.value)} />
      <button disabled={!api || busy}>DBへ登録</button>
    </form>
    <button disabled={!api || busy} onClick={() => {
      if (api) void execute(async () => setRows(await api.getTests()));
    }}>一覧取得</button>
    <ul>{rows.map((row) => <li key={row.id}>#{row.id} {row.name} / {row.createdAt}</li>)}</ul>
    {busy && <p>処理中...</p>}
    {error && <p role="alert">{error}</p>}
  </main>;
}
