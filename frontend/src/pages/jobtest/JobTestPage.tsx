import {
  useEffect,
  useMemo,
  useRef,
  useState,
  type FormEvent,
} from "react";
import { Link } from "react-router-dom";

import {
  JobTestApi,
  type CompletedTestJobResult,
  type CreateTestJobResponse,
} from "../../api/jobtest/jobTestApi";
import {
  signIn,
  type AuthSession,
} from "../../auth/cognitoAuth";
import {
  loadRuntimeConfig,
  type RuntimeConfig,
} from "../../config/runtimeConfig";
import "./JobTestPage.css";

const POLLING_INTERVAL_MILLISECONDS = 2_000;
const MAX_POLLING_ATTEMPTS = 30;

type FlowState = "waiting" | "queued" | "processing" | "completed";

function toMessage(error: unknown): string {
  return error instanceof Error
    ? error.message
    : String(error);
}

function wait(
  milliseconds: number,
  signal: AbortSignal,
): Promise<void> {
  if (signal.aborted) {
    return Promise.reject(
      new DOMException("処理を中止しました", "AbortError"),
    );
  }

  return new Promise((resolve, reject) => {
    const onAbort = () => {
      window.clearTimeout(timeoutId);
      reject(new DOMException("処理を中止しました", "AbortError"));
    };

    const timeoutId = window.setTimeout(() => {
      signal.removeEventListener("abort", onAbort);
      resolve();
    }, milliseconds);

    signal.addEventListener(
      "abort",
      onAbort,
      { once: true },
    );
  });
}

function stepState(
  flowState: FlowState,
  step: FlowState,
): "waiting" | "active" | "done" {
  const order: FlowState[] = [
    "waiting",
    "queued",
    "processing",
    "completed",
  ];
  const currentIndex = order.indexOf(flowState);
  const stepIndex = order.indexOf(step);

  if (stepIndex < currentIndex || flowState === "completed") {
    return "done";
  }

  return stepIndex === currentIndex ? "active" : "waiting";
}

export default function JobTestPage() {
  const [config, setConfig] = useState<RuntimeConfig | null>(null);
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [session, setSession] = useState<AuthSession | null>(null);
  const [payload, setPayload] = useState("music flows lambda test");
  const [createdJob, setCreatedJob] =
    useState<CreateTestJobResponse | null>(null);
  const [completedResult, setCompletedResult] =
    useState<CompletedTestJobResult | null>(null);
  const [flowState, setFlowState] = useState<FlowState>("waiting");
  const [pollingAttempt, setPollingAttempt] = useState(0);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const [isLoggingIn, setIsLoggingIn] = useState(false);
  const [isRunning, setIsRunning] = useState(false);
  const pollingController = useRef<AbortController | null>(null);
  const isLocalWorker = config?.workerExecutionMode === "local";

  useEffect(() => {
    loadRuntimeConfig()
      .then(setConfig)
      .catch((cause: unknown) => {
        setError(toMessage(cause));
      });

    return () => {
      pollingController.current?.abort();
    };
  }, []);

    const api = useMemo(() => {

       if (!config) {
         return null;
       }

       /*
        * Local Workerモードでは、
        * Spring Bootへ直接接続する。Cognito Access Tokenは使用しない。
        */
       if (config.workerExecutionMode === "local") {
         return new JobTestApi(
           config.directApiBaseUrl,
         );
       }

       /*
        * LambdaモードではCognito認証が必要。
        */
       if (!session) {
         return null;
       }
   
       return new JobTestApi(
         config.apiBaseUrl,
         session.accessToken,
       );
    }, [config, session]);

  const login = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();

    if (!config) {
      return;
    }

    setError("");
    setMessage("");
    setIsLoggingIn(true);

    try {
      const result = await signIn(
        config,
        username,
        password,
      );
      setSession(result);
      setMessage("Cognitoログインに成功しました");
    } catch (cause) {
      setError(toMessage(cause));
    } finally {
      setIsLoggingIn(false);
    }
  };

  const logout = () => {
    pollingController.current?.abort();
    setSession(null);
    setCreatedJob(null);
    setCompletedResult(null);
    setFlowState("waiting");
    setPollingAttempt(0);
    setIsRunning(false);
    setError("");
    setMessage("ログアウトしました");
  };

  
  const runConnectionTest = async (
    event: FormEvent<HTMLFormElement>,
  ) => {
    event.preventDefault();

    if (!api) {
      if (!config) {
        setError("Runtime Configを読み込めていません");
        return;
      }
    
      if (config.workerExecutionMode === "lambda") {
        setError("Lambdaモードでは先にCognitoへログインしてください");
        return;
      }
    
      setError("Spring Boot直接接続用のAPI設定を確認してください");
      return;
    }

    const trimmedPayload = payload.trim();

    if (!trimmedPayload) {
      setError("SQSへ送信するpayloadを入力してください");
      return;
    }

    pollingController.current?.abort();
    const controller = new AbortController();
    pollingController.current = controller;

    setCreatedJob(null);
    setCompletedResult(null);
    setFlowState("waiting");
    setPollingAttempt(0);
    setError("");
    setMessage("ジョブを登録しています...");
    setIsRunning(true);

    try {
      const job = await api.createJob(
        trimmedPayload,
        controller.signal,
      );
      setCreatedJob(job);
      setFlowState("queued");
      setMessage("SQSへジョブを登録しました。処理結果を確認しています...");

      for (
        let attempt = 1;
        attempt <= MAX_POLLING_ATTEMPTS;
        attempt += 1
      ) {
        setPollingAttempt(attempt);

        const result = await api.getResult(
          job.jobId,
          controller.signal,
        );

        if (result.status === "COMPLETED") {
                
          setCompletedResult(result);
                
          const expectedProcessorType = config?.workerExecutionMode === "local"
                                        ? "LOCAL_WORKER"
                                        : "LAMBDA";

          /*
           * S3へ保存されたprocessorTypeを正とする。
           * 画面でLocal Workerを選択していても、実際にLambdaが処理していた場合は成功扱いにしない。
           */
          if (result.processorType !== expectedProcessorType) {
          
            throw new Error(
              [
                "期待したWorkerと実際に処理したWorkerが一致しません",
                `expected=${expectedProcessorType}`,
                `actual=${result.processorType}`,
                `jobId=${result.jobId}`,
                `sqsMessageId=${result.sqsMessageId}`,
              ].join(", "),
            );
          }
        
          setFlowState("completed");
        
          if (result.processorType === "LOCAL_WORKER") {
            setMessage("疎通確認に成功しました。Local Workerの処理結果をS3から取得できました。");
          } else {
            setMessage("疎通確認に成功しました。Worker Lambdaの処理結果をS3から取得できました。");
          }
          return;
        }

        setFlowState("processing");

        if (attempt < MAX_POLLING_ATTEMPTS) {
          await wait(
            POLLING_INTERVAL_MILLISECONDS,
            controller.signal,
          );
        }
      }

      throw new Error(
        [
          "60秒以内に処理が完了しませんでした。",
          "SQS、Worker、S3の状態を確認してください。",
          `workerExecutionMode=${config?.workerExecutionMode}`,
        ].join(" "),
      );
    } catch (cause) {
      if (
        cause instanceof DOMException
        && cause.name === "AbortError"
      ) {
        return;
      }

      setError(toMessage(cause));
      setMessage("");
    } finally {
      if (pollingController.current === controller) {
        pollingController.current = null;
      }
      setIsRunning(false);
    }
  };

  return (
    <main className="job-test-page">
      <h1>非同期ジョブ疎通確認</h1>
      <p>
        画面からジョブを登録し、
        SQS → Local Worker / Worker Lambda → S3
        の処理結果を確認します。
      </p>

      <nav>
        <Link to="/">トップ画面へ戻る</Link>
        {" / "}
        <Link to="/auth-test">認証確認画面へ</Link>
      </nav>

      <section>
        <h2>1. 接続設定</h2>
        {config ? (
          <dl>
            <dt>API Gateway</dt>
            <dd>{config.apiBaseUrl}</dd>
            <dt>Cognito endpoint</dt>
            <dd>{config.cognitoEndpointUrl}</dd>
          </dl>
        ) : (
          <p>設定読込中...</p>
        )}
      </section>

      <section>
        <h2>2. Cognitoログイン</h2>
        {isLocalWorker ? (
          <p>Local WorkerモードではSpring Bootへ直接接続するため、Cognitoログインは不要です。</p>
            ) : !session ? (
          <form onSubmit={login}>
            <label>
              ユーザー名
              <input
                type="email"
                value={username}
                autoComplete="username"
                placeholder="local-user@example.com"
                required
                onChange={(event) => setUsername(event.target.value)}
              />
            </label>
            <label>
              パスワード
              <input
                type="password"
                value={password}
                autoComplete="current-password"
                required
                onChange={(event) => setPassword(event.target.value)}
              />
            </label>
            <button
              type="submit"
              disabled={!config || isLoggingIn}
            >
              {isLoggingIn ? "ログイン中..." : "ログイン"}
            </button>
          </form>
        ) : (
          <>
            <p>ログイン済みです。</p>
            <button type="button" onClick={logout}>
              ログアウト
            </button>
          </>
        )}
      </section>

      <section>
        <h2>3. Worker実行モード</h2>
        {config ? (
          <dl>
            <dt>現在のWorker</dt>
            <dd>
              {isLocalWorker ? "Local Worker" : "Floci Worker Lambda"}
            </dd>
            <dt>実行モード</dt>
            <dd>
              {config.workerExecutionMode}
            </dd>
      
            <dt>現在のAPI接続先</dt>
            <dd>
              {isLocalWorker
                ? config.directApiBaseUrl
                : config.apiBaseUrl}
            </dd>
      
            <dt>期待するProcessor</dt>
            <dd>
              {isLocalWorker ? "LOCAL_WORKER" : "LAMBDA"}
            </dd>
          </dl>
        ) : (
          <p>Worker実行モードを確認しています...</p>
        )}
      </section>
      <section>
        <h2>4. ジョブ実行</h2>
        <form onSubmit={runConnectionTest}>
          <label>
            payload
            <textarea
              value={payload}
              maxLength={4096}
              required
              onChange={(event) => setPayload(event.target.value)}
            />
          </label>
          <button
            type="submit"
            disabled={!api || isRunning}
          >
            {isRunning ? "疎通確認中..." : "疎通確認を実行"}
          </button>
        </form>

        <ol className="job-test-flow" aria-label="疎通確認の進行状況">
          <li data-state={stepState(flowState, "waiting")}>
            画面
          </li>
          <li data-state={stepState(flowState, "queued")}>
            SQS
          </li>
          <li data-state={stepState(flowState, "processing")}>
            {isLocalWorker ? "Local Worker" : "Worker Lambda"}
          </li>
          <li data-state={stepState(flowState, "completed")}>
            S3
          </li>
        </ol>

        {isRunning && pollingAttempt > 0 && (
          <p>
            結果確認: {pollingAttempt} / {MAX_POLLING_ATTEMPTS}
          </p>
        )}
      </section>

      {createdJob && (
        <section className="job-test-result">
          <h2>ジョブ登録結果</h2>
          <pre>{JSON.stringify(createdJob, null, 2)}</pre>
        </section>
      )}

      {completedResult && (
        <section className="job-test-result">
          <h2>S3処理結果</h2>
          <pre>{JSON.stringify(completedResult, null, 2)}</pre>
        </section>
      )}

      {message && <p role="status">{message}</p>}

      {error && (
        <section className="job-test-error" role="alert">
          <h2>エラー</h2>
          <pre>{error}</pre>
        </section>
      )}
    </main>
  );
}
