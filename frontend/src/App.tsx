import { useMemo,useState,type FormEvent } from 'react'
import { TestsApi,type ApplicationHealth,type Tests,} from "./api/test/testsApi";
import {loadRuntimeConfig,type RuntimeConfig,} from "./config/runtimeConfig";
import './App.css'

type ApiMode = "direct" | "lambda";

function toErrorMessage(error: unknown): string {
  if (error instanceof Error) {
    return error.message;
  }

  return String(error);
}

function App() {
  const [config, setConfig] = useState<RuntimeConfig | null>(null);
  const [mode, setMode] = useState<ApiMode>("direct");
  const [applicationHealth, setApplicationHealth] = useState<ApplicationHealth | null>(null);
  const [projects, setProjects] = useState<Tests[]>([]);
  const [projectName, setProjectName] = useState("");

  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  // APIクライアントのインスタンスを作成する
  const api = useMemo(() => {
    if (!config) {
      return null;
    }

    const baseUrl = mode === "direct" ? config.directApiBaseUrl : config.apiBaseUrl;
    return new TestsApi(baseUrl);
  }, [config, mode]);

  // 設定ファイルを読み込む
  const initialize = async () => {
    setError(null);
    setLoading(true);

    try {
      const loadedConfig = await loadRuntimeConfig();
      setConfig(loadedConfig);

    } catch (cause) {
      setError(toErrorMessage(cause));
    } finally {
      setLoading(false);
    }
  };

  // 接続確認を実行する
  const runConnectionTest = async () => {
    if (!api) {
      setError("先に設定ファイルを読み込んでください");
      return;
    }

    setError(null);
    setLoading(true);

    try {
      const [
        applicationResult,
        projectResult,
      ] = await Promise.all([
        api.getApplicationHealth(),
        api.getTests(),
      ]);

      setApplicationHealth(applicationResult);
      setProjects(projectResult);
    } catch (cause) {
      setError(toErrorMessage(cause));
    } finally {
      setLoading(false);
    }
  };

  const createProject = async (
    event: FormEvent<HTMLFormElement>,
  ) => {
    event.preventDefault();

    if (!api) {
      setError("APIの接続先が設定されていません");
      return;
    }

    const trimmedName = projectName.trim();

    if (!trimmedName) {
      setError("プロジェクト名を入力してください");
      return;
    }

    setError(null);
    setLoading(true);

    try {
      await api.createTest({
        name: trimmedName,
      });

      const updatedProjects =
        await api.getTests();

      setProjects(updatedProjects);
      setProjectName("");
    } catch (cause) {
      setError(toErrorMessage(cause));
    } finally {
      setLoading(false);
    }
  };

  return (
    <main>
      <h1>Musicflows 疎通確認</h1>

      <section>
        <h2>1. ランタイム設定</h2>

        <button
          type="button"
          onClick={initialize}
          disabled={loading}
        >
          local-config.jsonを読み込む
        </button>

        {config && (
          <dl>
            <dt>Spring Boot直接</dt>
            <dd>{config.directApiBaseUrl}</dd>

            <dt>API Gateway / Lambda</dt>
            <dd>{config.apiBaseUrl}</dd>
          </dl>
        )}
      </section>

      <section>
        <h2>2. 接続経路</h2>

        <label>
          <input
            type="radio"
            name="api-mode"
            value="direct"
            checked={mode === "direct"}
            onChange={() => setMode("direct")}
          />
          Spring Bootへ直接接続
        </label>

        <label>
          <input
            type="radio"
            name="api-mode"
            value="lambda"
            checked={mode === "lambda"}
            onChange={() => setMode("lambda")}
          />
          API Gateway / Lambda経由
        </label>

        {api && (
          <p>
            接続先: <code>{api.getBaseUrl()}</code>
          </p>
        )}
      </section>

      <section>
        <h2>3. プロジェクト登録</h2>

        <form onSubmit={createProject}>
          <input
            type="text"
            value={projectName}
            maxLength={100}
            placeholder="プロジェクト名"
            onChange={(event) =>
              setProjectName(event.target.value)
            }
          />

          <button
            type="submit"
            disabled={!api || loading}
          >
            DBへ登録
          </button>
        </form>

        <ul>
          {projects.map((project) => (
            <li key={project.id}>
              #{project.id} {project.name}
              {" / "}
              {project.createdAt}
            </li>
          ))}
        </ul>
      </section>

      {loading && <p>処理中...</p>}

      {error && (
        <section>
          <h2>エラー</h2>
          <pre>{error}</pre>
        </section>
      )}
    </main>
  );

}

export default App
