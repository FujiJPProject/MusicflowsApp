export type AuthenticatedUser = {
  sub: string;
  username: string;
  tokenUse: string;
  clientId: string;
  issuer: string;
};

export type Test = {
  id: number;
  name: string;
  createdAt: string;
};

export class AuthTestApi {

  private readonly baseUrl: string;
  private readonly accessToken?: string;

  constructor(
    baseUrl: string,
    accessToken?: string,
  ) {

    this.baseUrl =
      baseUrl.replace(/\/+$/, "");

    this.accessToken =
      accessToken;
  }

  getCurrentUser(): Promise<AuthenticatedUser> {
    return this.request(
      "/api/auth/me",
    );
  }

  getTests(): Promise<Test[]> {
    return this.request(
      "/api/tests",
    );
  }

  createTest(
    name: string,
  ): Promise<Test> {

    return this.request(
      "/api/tests",
      {
        method: "POST",

        headers: {
          "Content-Type":
            "application/json",
        },

        body: JSON.stringify({
          name,
        }),
      },
    );
  }

  private async request<T>(
    path: string,
    init?: RequestInit,
  ): Promise<T> {

    const headers =
      new Headers(init?.headers);

    /*
     * ログイン済みの場合だけ
     * Cognito Access Tokenを送る。
     */
    if (this.accessToken) {
      headers.set(
        "Authorization",
        `Bearer ${this.accessToken}`,
      );
    }

    const response =
      await fetch(
        `${this.baseUrl}${path}`,
        {
          ...init,
          headers,
        },
      );

    const text =
      await response.text();

    if (!response.ok) {
      throw new Error(
        [
          `status=${response.status}`,
          text,
        ]
          .filter(Boolean)
          .join(": "),
      );
    }

    if (!text) {
      return undefined as T;
    }

    return JSON.parse(text) as T;
  }
}