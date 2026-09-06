export type RuntimeConfig = {
  apiBaseUrl: string;
  directApiBaseUrl: string;
  cognitoUserPoolId: string;
  cognitoClientId: string;
  awsRegion: string;
  cognitoEndpointUrl: string;
};

let cachedConfig: RuntimeConfig | undefined;

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

  if (!config.apiBaseUrl) {
    throw new Error(
      "local-config.jsonにapiBaseUrlがありません",
    );
  }

  cachedConfig = {
    apiBaseUrl: config.apiBaseUrl,
    directApiBaseUrl:
      config.directApiBaseUrl ?? "http://localhost:8080",
    cognitoUserPoolId: config.cognitoUserPoolId ?? "",
    cognitoClientId: config.cognitoClientId ?? "",
    awsRegion: config.awsRegion ?? "ap-northeast-1",
    cognitoEndpointUrl:
      config.cognitoEndpointUrl ?? "http://localhost:4566",
  };

  return cachedConfig;
}