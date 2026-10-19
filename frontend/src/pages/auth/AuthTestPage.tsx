import { useEffect, useMemo, useState, type FormEvent } from "react";
import { Link } from "react-router-dom";

import {
  AuthTestApi,
  type AuthenticatedUser,
  type Test,
} from "../../api/auth/authTestApi";
import { signIn, type AuthSession } from "../../auth/cognitoAuth";
import {
  beginPkceLogin,
  clearPkceSession,
  getPkceSession,
} from "../../auth/cognitoPkce";
import {
  loadRuntimeConfig,
  type RuntimeConfig,
} from "../../config/runtimeConfig";

/** APIや設定読込で発生した値を、画面表示用の文字列に変換する。 */
function toMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

export default function AuthTestPage() {
  const [config, setConfig] = useState<RuntimeConfig | null>(null);
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [session, setSession] = useState<AuthSession | null>(
    () => getPkceSession(),
  );
  const [currentUser, setCurrentUser] =
    useState<AuthenticatedUser | null>(null);
  const [tests, setTests] = useState<Test[]>([]);
  const [testName, setTestName] = useState("");
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");

  // App.tsxとは独立して、この画面でruntime configを読み込む。
  useEffect(() => {
    loadRuntimeConfig()
      .then(setConfig)
      .catch((cause) => setError(toMessage(cause)));
  }, []);

  // 設定またはログイン状態が変わったとき、認証情報付きAPIクライアントを更新する。
  const api = useMemo(() => {
    if (!config) {
      return null;
    }

    return new AuthTestApi(config.apiBaseUrl, session?.accessToken);
  }, [config, session]);

  // Cognitoで認証し、取得したセッションを後続のAPI呼び出しに使う。
  const login = async (event: FormEvent) => {
    event.preventDefault();

    if (!config) {
      setError("Runtime Configを読み込めていません");
      return;
    }

    if (config.deploymentStage !== "local") {
      setError("このログイン方式はlocal環境専用です。Cognito OAuth認証を使用してください");
      return;
    }

    setError("");
    setMessage("");

    try {
      const result = await signIn(config, username, password);
      setSession(result);
      setMessage("Cognitoログインに成功しました");
    } catch (cause) {
      setError(toMessage(cause));
    }
  };

  const loginWithPkce = async () => {
    if (!config) {
      setError("Runtime Configを読み込めていません");
      return;
    }

    if (config.deploymentStage === "local") {
      setError("local環境では従来のCognitoログインを使用してください");
      return;
    }

    setError("");
    setMessage("");

    try {
      await beginPkceLogin(config,"/auth-test");
    } catch (cause) {
      setError(toMessage(cause));
    }
  };

  // セッションと取得済みのユーザー情報・テスト一覧をクリアする。
  const logout = () => {
    clearPkceSession()
    setSession(null);
    setCurrentUser(null);
    setTests([]);
    setMessage("ログアウトしました");
  };

  // JWTを付けずに保護APIを呼び、未認証アクセスが拒否されることを確認する。
  const checkWithoutToken = async () => {
    if (!config) {
      return;
    }

    setError("");
    setMessage("");

    try {
      const noTokenApi = new AuthTestApi(config.apiBaseUrl);
      await noTokenApi.getCurrentUser();
      setError("認証なしでAPIへアクセスできてしまいました");
    } catch (cause) {
      setMessage(`期待どおり拒否されました: ${toMessage(cause)}`);
    }
  };

  // JWTで認証されたユーザー情報を取得する。
  const loadCurrentUser = async () => {
    if (!api) {
      return;
    }

    setError("");

    try {
      const user = await api.getCurrentUser();
      setCurrentUser(user);
    } catch (cause) {
      setError(toMessage(cause));
    }
  };

  // 保護されたDB APIからテスト一覧を取得する。
  const loadTests = async () => {
    if (!api) {
      return;
    }

    setError("");

    try {
      const result = await api.getTests();
      setTests(result);
    } catch (cause) {
      setError(toMessage(cause));
    }
  };

  // 入力を検証してテストを登録し、登録後の一覧を再取得する。
  const createTest = async (event: FormEvent) => {
    event.preventDefault();

    if (!api) {
      return;
    }

    const name = testName.trim();
    if (!name) {
      return;
    }

    setError("");

    try {
      await api.createTest(name);
      setTests(await api.getTests());
      setTestName("");
    } catch (cause) {
      setError(toMessage(cause));
    }
  };

  return (
    <main>
      <h1>Cognito / JWT 疎通確認</h1>

      <p>
        <Link to="/">第1段階の画面へ戻る</Link>
        {" / "}
        <Link to="/jobtest">SQS / Lambda / S3 疎通確認画面へ</Link>
      </p>

      <section>
        <h2>1. 接続設定</h2>
        {config ? (
          <dl>
            <dt>API Gateway</dt>
            <dd>{config.apiBaseUrl}</dd>
            <dt>Cognito endpoint</dt>
            <dd>{config.cognitoEndpointUrl}</dd>
            <dt>User Pool ID</dt>
            <dd>{config.cognitoUserPoolId}</dd>
            <dt>Client ID</dt>
            <dd>{config.cognitoClientId}</dd>
          </dl>
        ) : (
          <p>設定読込中...</p>
        )}
      </section>

      <section>
        <h2>2. 未認証アクセス確認</h2>
        <button
          type="button"
          onClick={checkWithoutToken}
          disabled={!config}
        >
          JWTなしで保護APIを呼ぶ
        </button>
      </section>

      <section>
        <h2>3. Cognitoログイン</h2>
        {!config ? (
            /** Runtime Configの読み込み待ち */
            <p>設定読込中...</p>
          ) : session ? (
           /** ログイン済み */
          <>
            <p>ログイン済み</p>   
            <button
              type="button"
              onClick={logout}
            >
              ログアウト
            </button>
          </>
          ) : config.deploymentStage === "local" ? (
          <form onSubmit={login}>
            <input
              type="email"
              value={username}
              placeholder="local-user@example.com"
              autoComplete="username"
              required
              onChange={(event) => setUsername(event.target.value)}
            />
            <input
              type="password"
              value={password}
              placeholder="パスワード"
              autoComplete="current-password"
              required
              onChange={(event) => setPassword(event.target.value)}
            />
            <button type="submit">ログイン</button>
          </form>
        ) : (
          <>
            <button
              type="button"
              onClick={loginWithPkce}
              >
               Cognitoでログイン
            </button>
          </>
        )}
      </section>

      <section>
        <h2>4. JWT認証ユーザー確認</h2>
        <button
          type="button"
          onClick={loadCurrentUser}
          disabled={!session}
        >
          /api/auth/me を呼ぶ
        </button>
        {currentUser && (
          <pre>{JSON.stringify(currentUser, null, 2)}</pre>
        )}
      </section>

      <section>
        <h2>5. 保護DB API確認</h2>
        <button type="button" onClick={loadTests} disabled={!session}>
          /api/tests を取得
        </button>
        <ul>
          {tests.map((test) => (
            <li key={test.id}>
              #{test.id} {test.name} / {test.createdAt}
            </li>
          ))}
        </ul>
      </section>

      <section>
        <h2>6. 保護POST確認</h2>
        <form onSubmit={createTest}>
          <input
            type="text"
            value={testName}
            maxLength={100}
            placeholder="JWT経由登録テスト"
            onChange={(event) => setTestName(event.target.value)}
          />
          <button type="submit" disabled={!session}>
            DBへ登録
          </button>
        </form>
      </section>

      {message && <p>{message}</p>}
      {error && (
        <section>
          <h2>エラー</h2>
          <pre>{error}</pre>
        </section>
      )}
    </main>
  );
}
