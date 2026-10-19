import { useEffect, useRef, useState } from "react";

import { finishPkceLogin } from "../../auth/cognitoPkce";
import type { RuntimeConfig } from "../../config/runtimeConfig";

type Props = {
  config: RuntimeConfig;
};

/**
 * CognitoのPKCE認証のコールバック画面。
 * @param props
 * @returns 
 */
export default function AuthCallbackPage({config}: Props) {
  const started = useRef(false);
  const [error, setError] = useState("");

  useEffect(() => {
    // Strict Mode などで effect が再実行されても、認証処理は一度だけ実行する。
    if (started.current) {
      return;
    }

    started.current = true;

    // PKCE 認証を完了し、失敗した場合は画面にエラーを表示する。
    finishPkceLogin(config).catch((cause: unknown) => {
      setError(
        cause instanceof Error
          ? cause.message
          : String(cause),
      );
    });
  }, [config]);

  return (
    <main>
      <h1>Cognito認証</h1>

      {error ? (
        <p role="alert">{error}</p>
      ) : (
        <p>認証結果を確認しています...</p>
      )}
    </main>
  );
}