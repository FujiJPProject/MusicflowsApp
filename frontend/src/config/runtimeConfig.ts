// Workerの実行モードの型定義
export type WorkerExecutionMode = "local" | "lambda";

// 環境変数から取得する設定値の型定義
export type DeploymentStage = "local" | "dev" | "production";

/**
 * RuntimeConfig型の定義
 */
export type RuntimeConfig = {
  /** デプロイメントステージ */
  deploymentStage: DeploymentStage;
  /** APIのベースURL */
  apiBaseUrl: string;
  /** APIのベースURL（local環境でのみ使用） */
  directApiBaseUrl?: string;
  /** CognitoのユーザープールID */
  cognitoUserPoolId: string;
  /** CognitoのクライアントID */
  cognitoClientId: string;
  /** AWSのリージョン */
  awsRegion: string;
  /** CognitoのエンドポイントURL（local環境でのみ使用） */
  cognitoEndpointUrl?: string;
  // AWS向けOAuth認証で使用
  cognitoDomain?: string;
  /** Workerの実行モード */
  workerExecutionMode: WorkerExecutionMode;
  /** テストページの有効化フラグ */
  testPagesEnabled: boolean;
};

// キャッシュされたRuntimeConfigのインスタンス
let cachedConfig: RuntimeConfig | undefined;

/**
 * 必須の文字列型の値を取得する関数
 * @param value 
 * @param name 
 * @returns 
 */
function requireString(
  value: unknown,
  name: string,
): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error(`Runtime Configの${name}が設定されていません`);
  }

  return value.trim();
}

/**
 * 任意の文字列型の値を取得する関数
 * @param value 
 * @param name 
 * @returns 
 */
function optionalString(
  value: unknown,
  name: string,
): string | undefined {
  if (value === undefined) {
    return undefined;
  }

  return requireString(value, name);
}

/**
 * 指定された文字列が有効なURLであることを検証する関数
 * @param value 
 * @param name 
 * @returns 
 */
function requireUrl(
  value: string,
  name: string,
): URL {
  try {
    const url = new URL(value);

    // URLの形式を検証
    // URLのプロトコルがhttpまたはhttpsであること、
    // ホスト名が存在すること、
    // ユーザー名、パスワード、検索パラメータ、ハッシュが含まれていないことを確認
    if (
      !["http:", "https:"].includes(url.protocol) ||
      !url.hostname ||
      url.username ||
      url.password ||
      url.search ||
      url.hash
    ) {
      throw new Error("Invalid URL");
    }

    return url;
  } catch {
    throw new Error(`Runtime Configの${name}が不正なURLです`);
  }
}

/**
 *  指定されたホスト名がループバックアドレスかどうかを判定する関数
 * @param hostname 
 * @returns 
 */
function isLoopbackHost(hostname: string): boolean {
  const host = hostname
    .toLowerCase()
    .replace(/\.$/, "");

  if (
    host === "localhost" ||
    host.endsWith(".localhost") ||
    host === "[::1]" ||
    host === "[::]" ||
    host === "0.0.0.0"
  ) {
    return true;
  }

  // WHATWG URLによる正規化後のIPv4を判定
  const ipv4 = host.match(
    /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/,
  );

  if (ipv4) {
    const first = Number(ipv4[1]);
    return first === 0 || first === 127;
  }

  // IPv4-mapped IPv6も拒否
  if (
    host.startsWith("[::ffff:7f") ||
    host.startsWith("[::ffff:0:7f")
  ) {
    return true;
  }

  return false;
}

/**
 * AWS環境で使用するURLの検証関数
 * @param value 
 * @param name 
 */
function requireAwsUrl(
  value: string,
  name: string,
): void {
  const url = requireUrl(value, name);

  if (url.protocol !== "https:") {
    throw new Error(`AWS環境の${name}にはHTTPSが必要です`);
  }

  if (isLoopbackHost(url.hostname)) {
    throw new Error(`AWS環境の${name}にはlocalhostを指定できません`);
  }
}

/**
 * RuntimeConfigの検証関数
 * @param value 
 * @returns 
 */
function validateConfig(
  value: unknown,
): RuntimeConfig {

  // JSON形式の検証
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Runtime ConfigのJSON形式が不正です");
  }

  const raw = value as Record<string, unknown>;

  const deploymentStage = raw.deploymentStage;

  if (
    deploymentStage !== "local" &&
    deploymentStage !== "dev" &&
    deploymentStage !== "production"
  ) {
    throw new Error("Runtime ConfigのdeploymentStageが不正です");
  }

  const apiBaseUrl = requireString(raw.apiBaseUrl, "apiBaseUrl");

  const cognitoUserPoolId = requireString(raw.cognitoUserPoolId,"cognitoUserPoolId");

  const cognitoClientId = requireString(raw.cognitoClientId,"cognitoClientId");

  const awsRegion = requireString(raw.awsRegion,"awsRegion");

  const directApiBaseUrl = optionalString(raw.directApiBaseUrl,"directApiBaseUrl");

  const cognitoEndpointUrl = optionalString(raw.cognitoEndpointUrl,"cognitoEndpointUrl");

  const cognitoDomain = optionalString(raw.cognitoDomain,"cognitoDomain");

  requireUrl(apiBaseUrl, "apiBaseUrl");

  // local環境でのみ使用するURLの検証
  if (
    raw.workerExecutionMode !== "local" &&
    raw.workerExecutionMode !== "lambda"
  ) {
    throw new Error("workerExecutionModeが不正です");
  }

  // testPagesEnabledの型検証
  if (typeof raw.testPagesEnabled !== "boolean") {
    throw new Error( "testPagesEnabledはboolean型で指定してください");
  }

  // local環境ではdirectApiBaseUrlとcognitoEndpointUrlが必須
  if (deploymentStage === "local") {
    requireUrl(
      requireString(directApiBaseUrl,"directApiBaseUrl"),
      "directApiBaseUrl",
    );

    requireUrl(
      requireString(cognitoEndpointUrl,"cognitoEndpointUrl"),
      "cognitoEndpointUrl",
    );
  } else {

    requireAwsUrl(apiBaseUrl, "apiBaseUrl");

    if (directApiBaseUrl !== undefined || cognitoEndpointUrl !== undefined) {
      throw new Error("AWS環境ではローカル接続先を設定できません");
    }

    if (raw.workerExecutionMode !== "lambda") {
      throw new Error("AWS環境ではworkerExecutionModeはlambdaです");
    }

    if (cognitoDomain !== undefined) {
      requireAwsUrl(cognitoDomain, "cognitoDomain");
    }

    // devで疎通確認画面を使用する場合はOAuth必須
    if (deploymentStage === "dev" && raw.testPagesEnabled && !cognitoDomain) {
      throw new Error("devでテスト画面を使用するにはcognitoDomainが必要です");
    }
  }

  // productionでは疎通確認画面を使用できない
  if (deploymentStage === "production" && raw.testPagesEnabled) {
    throw new Error("productionではテスト画面を有効化できません");
  }

  return {
    deploymentStage,
    apiBaseUrl,
    directApiBaseUrl,
    cognitoUserPoolId,
    cognitoClientId,
    awsRegion,
    cognitoEndpointUrl,
    cognitoDomain,
    workerExecutionMode: raw.workerExecutionMode,
    testPagesEnabled: raw.testPagesEnabled,
  };
}

export async function loadRuntimeConfig():
  Promise<RuntimeConfig> {
  
  // キャッシュが存在する場合はそれを返す
  if (cachedConfig) {
    return cachedConfig;
  }

  // local-config.jsonを取得
  const response = await fetch(
    "/config/local-config.json",
    { cache: "no-store" },
  );

  // HTTPステータスコードが200以外の場合はエラーを投げる
  if (!response.ok) {
    throw new Error(`Runtime Config取得失敗: HTTP ${response.status}`);
  }

  const raw: unknown = await response.json();
  const config = validateConfig(raw);

  cachedConfig = config;
  return config;
}