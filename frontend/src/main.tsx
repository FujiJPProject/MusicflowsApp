import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { BrowserRouter, Link, Route, Routes } from "react-router-dom";
import App from "./App";
import {
  loadRuntimeConfig,
  type RuntimeConfig,
} from "./config/runtimeConfig";
import "./index.css";
import AuthCallbackPage from "./pages/auth/AuthCallbackPage";
import AuthTestPage from "./pages/auth/AuthTestPage";
import JobTestPage from "./pages/jobtest/JobTestPage";

const rootElement = document.getElementById("root");

if (!rootElement) {
  throw new Error("root要素がありません");
}

const root = createRoot(rootElement);

function Application({ config }: {
  config: RuntimeConfig;
}) {
  // ローカル環境では通常のアプリ画面を表示します。
  const isLocal = config.deploymentStage === "local";
  const testsEnabled = config.testPagesEnabled;

  return (
    <StrictMode>
      <BrowserRouter>
        <Routes>
          {/* 環境に応じてホーム画面を切り替えます。 */}
          <Route
            path="/"
            element={
              isLocal ? (
                <App />
              ) : testsEnabled ? (
                <main>
                  <h1>Musicflows 開発用画面</h1>
                  <Link to="/jobtest">
                    ジョブ疎通確認へ
                  </Link>
                </main>
              ) : (
                <main>
                  <h1>Musicflows</h1>
                  <p>アプリケーション準備中</p>
                </main>
              )
            }
          />

          {/* テスト用ルートは設定で有効な場合のみ登録します。 */}
          {testsEnabled && (
            <Route
              path="/auth-test"
              element={<AuthTestPage />}
            />
          )}

          {testsEnabled && (
            <Route
              path="/jobtest"
              element={<JobTestPage />}
            />
          )}

          {/* 認証コールバックはローカル以外でのみ受け付けます。 */}
          {testsEnabled && !isLocal && (
            <Route
              path="/auth/callback"
              element={
                <AuthCallbackPage config={config} />
              }
            />
          )}

          <Route
            path="*"
            element={
              <main>
                <h1>404</h1>
                <p>ページが見つかりません</p>
              </main>
            }
          />
        </Routes>
      </BrowserRouter>
    </StrictMode>
  );
}

// ランタイム設定の読み込み後にアプリを描画します。
loadRuntimeConfig()
  .then((config) => {
    root.render(<Application config={config} />);
  })
  .catch((cause: unknown) => {
    const message =
      cause instanceof Error
        ? cause.message
        : String(cause);

      // 設定の読み込みに失敗した場合は、エラー内容を画面に表示します。
    root.render(
      <main>
        <h1>アプリケーション設定エラー</h1>
        <p role="alert">{message}</p>
      </main>,
    );
  });