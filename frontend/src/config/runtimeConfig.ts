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
  awsRegion?: string;
  /** CognitoのエンドポイントURL（local環境でのみ使用） */
  cognitoEndpointUrl?: string;
  /** Workerの実行モード */
  workerExecutionMode: WorkerExecutionMode;
  /** テストページの有効化フラグ */
  testPagesEnabled: boolean;
};

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
  if (typeof value !== "string" || value.trim() === "") {
    throw new Error(`Runtime Configの${name}が設定されていません`);
  }
  return value;
}

function assertProductionUrl(
  value: string,
  name: string,
): void {
  const url = new URL(value);
  const localhostHosts = new Set([
    "localhost", // IPv4 localhost
    "127.0.0.1", 
    "::1", // IPv6 localhost
    "[::1]",
  ]);

  // production環境ではlocalhostを指定できないようにする
  if (localhostHosts.has(url.hostname)) {
    throw new Error( `productionでは${name}にlocalhostを指定できません`);
  }
}

export async function loadRuntimeConfig(): Promise<RuntimeConfig> {
  if (cachedConfig) {
    return cachedConfig;
  }

  const response = await fetch("/config/local-config.json", {
    cache: "no-store",
  });

  if (!response.ok) {
    throw new Error(
      `設定ファイルを取得できませんでした: ${response.status}`,
    );
  }

  const config = (await response.json()) as Partial<RuntimeConfig>;

  const apiBaseUrl = requireString(config.apiBaseUrl, "apiBaseUrl");
  const cognitoUserPoolId = requireString(config.cognitoUserPoolId, "cognitoUserPoolId");
  const cognitoClientId = requireString(config.cognitoClientId, "cognitoClientId");
  const awsRegion = requireString(config.awsRegion, "awsRegion");

  // deploymentStageを検証
  if (
    config.deploymentStage !== "local"
    && config.deploymentStage !== "dev"
    && config.deploymentStage !== "production"
  ) {
      throw new Error("Runtime ConfigのdeploymentStageが不正です");
  }

  const deploymentStage = config.deploymentStage;

  // Workerモードを検証
  if (config.workerExecutionMode !== "local"
    && config.workerExecutionMode !== "lambda"
  ) {
    throw new Error("Runtime ConfigのworkerExecutionModeが不正です");
  }

  // production環境ではlocalhostを指定できないようにする
  if (config.deploymentStage === "production") {

    assertProductionUrl(apiBaseUrl,"apiBaseUrl");
    if (config.testPagesEnabled) {
      throw new Error("productionではtestPagesEnabledをtrueにできません");
    }
  }

  // local環境ではdirectApiBaseUrlとcognitoEndpointUrlが必須
  if (config.deploymentStage === "local") {
    requireString(config.directApiBaseUrl,"directApiBaseUrl",);
    requireString(config.cognitoEndpointUrl,"cognitoEndpointUrl",);
}

  cachedConfig = {
    deploymentStage: deploymentStage,
    apiBaseUrl: apiBaseUrl,
    directApiBaseUrl: config.directApiBaseUrl,
    cognitoUserPoolId: cognitoUserPoolId,
    cognitoClientId: cognitoClientId,
    awsRegion: awsRegion,
    cognitoEndpointUrl: config.cognitoEndpointUrl,
    workerExecutionMode: config.workerExecutionMode,
    testPagesEnabled: config.testPagesEnabled  === true,
  };

  return cachedConfig;
}