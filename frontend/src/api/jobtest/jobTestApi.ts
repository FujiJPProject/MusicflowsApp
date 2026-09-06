export type CreateTestJobResponse = {
  jobId: string;
  status: "QUEUED";
  resultKey: string;
};

export type ProcessingTestJobResult = {
  jobId: string;
  status: "PROCESSING";
};

export type CompletedTestJobResult = {
  jobId: string;
  status: "COMPLETED";
  requestedBy: string;
  processedPayload: string;
  processedAt: string;
};

export type TestJobResult =
  | ProcessingTestJobResult
  | CompletedTestJobResult;

export class JobTestApi {
  private readonly baseUrl: string;
  private readonly accessToken: string;

  constructor(
    baseUrl: string,
    accessToken: string,
  ) {
    this.baseUrl = baseUrl.replace(/\/+$/, "");
    this.accessToken = accessToken;
  }

  createJob(
    payload: string,
    signal?: AbortSignal,
  ): Promise<CreateTestJobResponse> {
    return this.request(
      "/api/test-jobs",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ payload }),
        signal,
      },
    );
  }

  getResult(
    jobId: string,
    signal?: AbortSignal,
  ): Promise<TestJobResult> {
    return this.request(
      `/api/test-jobs/${encodeURIComponent(jobId)}/result`,
      { signal },
    );
  }

  private async request<T>(
    path: string,
    init?: RequestInit,
  ): Promise<T> {
    const headers = new Headers(init?.headers);
    headers.set(
      "Authorization",
      `Bearer ${this.accessToken}`,
    );

    const response = await fetch(
      `${this.baseUrl}${path}`,
      {
        ...init,
        headers,
      },
    );

    const responseText = await response.text();

    if (!response.ok) {
      throw new Error(
        [
          "ジョブAPIの呼び出しに失敗しました",
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
