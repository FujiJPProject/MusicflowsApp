export type ApplicationHealth = {
  status: string;
  application: string;
};

export type Tests = {
  id: number;
  name: string;
  createdAt: string;
};

export type CreateProjectRequest = {
  name: string;
};

export class TestsApi {
  private readonly baseUrl: string;

  constructor(baseUrl: string) {
    this.baseUrl = baseUrl.replace(/\/+$/, "");
  }

  getBaseUrl(): string {
    return this.baseUrl;
  }

  getApplicationHealth(): Promise<ApplicationHealth> {
    return this.request<ApplicationHealth>(
      "/api/test/health",
    );
  }

  getTests(): Promise<Tests[]> {
    return this.request<Tests[]>(
      "/api/tests",
    );
  }

  createTest(
    request: CreateProjectRequest,
  ): Promise<Tests> {
    return this.request<Tests>(
      "/api/tests",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify(request),
      },
    );
  }

  private async request<T>(
    path: string,
    init?: RequestInit,
  ): Promise<T> {
    const normalizedPath = path.startsWith("/")
      ? path
      : `/${path}`;

    const response = await fetch(
      `${this.baseUrl}${normalizedPath}`,
      init,
    );

    const responseText = await response.text();

    if (!response.ok) {
      throw new Error(
        [
          `API呼び出しに失敗しました`,
          `status=${response.status}`,
          responseText,
        ]
          .filter(Boolean)
          .join(": "),
      );
    }

    if (!responseText) {
      return undefined as T;
    }

    return JSON.parse(responseText) as T;
  }
}