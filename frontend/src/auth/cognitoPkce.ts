import type { RuntimeConfig } from "../config/runtimeConfig";
import type { AuthSession } from "./cognitoAuth";

// 認証フローの一時情報とセッションをタブ単位で保存するキー。
const PENDING_KEY = "musicflows.pkce.pending";
const SESSION_KEY = "musicflows.pkce.session";

/**
 * 認証開始時に保存し、コールバック時の検証とトークン交換に使う情報。
 */
type PendingLogin = {
  /** PKCE verifier */
  verifier: string;
  /** OAuth state */
  state: string;
  /** 戻るURL */
  returnTo: "/jobtest" | "/auth-test";
};

/**
 * sessionStorage に保持するアクセストークンと有効期限。
 */
type StoredSession = {
  /** アクセストークン */
  accessToken: string;
  /** 有効期限（ミリ秒） */
  expiresAt: number;
};

/**
 * 暗号学的に安全な乱数から、URLで扱える文字列を生成する。
 * @param size 生成するバイト数
 */
function randomString(size: number): string {
  const bytes = crypto.getRandomValues(new Uint8Array(size));

  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-") // + を - に置換
    .replace(/\//g, "_") // / を _ に置換
    .replace(/=+$/, ""); // 末尾の = を削除
}

// バイト列を Base64 URL-safe 形式に変換する。
function base64Url(bytes: Uint8Array): string {

  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-") // + を - に置換
    .replace(/\//g, "_") // / を _ に置換
    .replace(/=+$/, ""); // 末尾の = を削除
}

// Cognito に登録したコールバックURLを返す。
function redirectUri(): string {
  return `${window.location.origin}/auth/callback`;
}

// Cognito ドメインが設定されていることを確認する。
function requireDomain(config: RuntimeConfig): string {
  if (!config.cognitoDomain) {
    throw new Error("cognitoDomainが設定されていません");
  }

  return config.cognitoDomain;
}

/**
 * PKCE認証フローを開始し、Cognitoの認可エンドポイントにリダイレクトする。
 * @param config 
 * @param returnTo 
 */
export async function beginPkceLogin(
  config: RuntimeConfig,
  returnTo: "/jobtest" | "/auth-test",
): Promise<void> {
  // local 環境では既存の Cognito 認証を利用する。
  if (config.deploymentStage === "local") {
    throw new Error("localでは既存のCognito認証を使用してください");
  }

  // PKCE認証フローのための verifier と state を生成する。
  const verifier = randomString(32);
  const state = randomString(32);

  // verifier の SHA-256 ハッシュを PKCE challenge として使用する。
  const digest = await crypto.subtle.digest(
    "SHA-256",new TextEncoder().encode(verifier));

  // challenge を Base64 URL-safe 形式に変換する。
  const challenge = base64Url(new Uint8Array(digest));

  const pending: PendingLogin = {
    verifier,
    state,
    returnTo,
  };

  // コールバック時に必要な値を、タブ内のストレージに保存する。
  sessionStorage.setItem(PENDING_KEY, JSON.stringify(pending));

  // Cognitoの認可エンドポイントにリダイレクトする。
  const url = new URL("/oauth2/authorize", requireDomain(config));

  // PKCE認証フローのパラメータを設定する。
  url.searchParams.set("response_type", "code");
  url.searchParams.set("client_id", config.cognitoClientId);
  url.searchParams.set("redirect_uri", redirectUri());
  url.searchParams.set("scope", "openid profile");
  url.searchParams.set("state", state);
  url.searchParams.set("code_challenge_method", "S256");
  url.searchParams.set("code_challenge", challenge);

  // 認可エンドポイントにリダイレクトする。
  window.location.assign(url.toString());
}

/**
 * PKCE認証フローを完了し、アクセストークンを取得する。
 */
export async function finishPkceLogin(
  config: RuntimeConfig,
): Promise<void> {
  const params = new URLSearchParams(
    window.location.search,
  );

  const code = params.get("code");
  const state = params.get("state");

  const raw = sessionStorage.getItem(PENDING_KEY);

  if (!raw || !code || !state) {
    throw new Error("OAuth認証情報が不足しています");
  }

  // 保存済み state と照合し、意図しないコールバックを拒否する。
  const pending = JSON.parse(raw) as PendingLogin;

  // 一度しか使用できないよう先に削除する
  sessionStorage.removeItem(PENDING_KEY);

  if (state !== pending.state) {
    throw new Error("OAuth stateが一致しません");
  }

  const url = new URL("/oauth2/token", requireDomain(config));

  const body = new URLSearchParams({
    grant_type: "authorization_code",
    client_id: config.cognitoClientId,
    code,
    redirect_uri: redirectUri(),
    code_verifier: pending.verifier,
  });

  // 認可コードと verifier を Cognito に送り、トークンを取得する。
  const response = await fetch(url.toString(), {
    method: "POST",
    headers: {"Content-Type": "application/x-www-form-urlencoded"},
    body,
    cache: "no-store",
  });

  if (!response.ok) {
    throw new Error(`OAuthトークン交換失敗: ${response.status}`);
  }

  const result = (await response.json()) as {
    access_token?: string;
    expires_in?: number;
  };

  if (!result.access_token || !result.expires_in) {
    throw new Error("OAuthトークン応答が不正です");
  }

  const session: StoredSession = {
    accessToken: result.access_token,
    expiresAt:
      Date.now() + result.expires_in * 1000,
  };

  // 取得したセッションを保存し、指定された画面へ戻る。
  sessionStorage.setItem(SESSION_KEY, JSON.stringify(session));

  const returnTo =
    pending.returnTo === "/auth-test"
      ? "/auth-test"
      : "/jobtest";

  window.location.replace(returnTo);
}

// 有効なセッションを返し、期限切れや不正なデータは削除する。
export function getPkceSession(): AuthSession | null {
  const raw = sessionStorage.getItem(SESSION_KEY);

  if (!raw) {
    return null;
  }

  try {
    const stored = JSON.parse(raw) as StoredSession;

    if (
      typeof stored.accessToken !== "string" ||
      typeof stored.expiresAt !== "number" ||
      stored.expiresAt <= Date.now() + 30_000
    ) {
      clearPkceSession();
      return null;
    }

    return {
      accessToken: stored.accessToken,
    };
  } catch {
    clearPkceSession();
    return null;
  }
}

// セッションと認証フローの一時情報をまとめて削除する。
export function clearPkceSession(): void {
  sessionStorage.removeItem(SESSION_KEY);
  sessionStorage.removeItem(PENDING_KEY);
}