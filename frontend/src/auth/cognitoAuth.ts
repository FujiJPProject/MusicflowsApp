import {
  AuthFlowType,
  CognitoIdentityProviderClient,
  InitiateAuthCommand,
} from "@aws-sdk/client-cognito-identity-provider";

import type {
  RuntimeConfig,
} from "../config/runtimeConfig";

export type AuthSession = {
  accessToken: string;
  idToken?: string;
  refreshToken?: string;
  expiresIn?: number;
};

/**
 * CognitoのUSER_PASSWORD_AUTHを使用して認証する
 * @param config Config情報
 * @param username ユーザー名 
 * @param password パスワード
 * @returns
 */
export async function signIn(
  config: RuntimeConfig,
  username: string,
  password: string,
): Promise<AuthSession> {

  if (config.deploymentStage !== "local") {
    throw new Error("USER_PASSWORD_AUTHはlocal環境専用です");
  }

  const client =
    new CognitoIdentityProviderClient({
      region: config.awsRegion,

      /*
       * ローカルではFlociをCognito endpointとして利用する。
       */
      endpoint: config.cognitoEndpointUrl,
    });

  try {

    const result = await client.send(
      new InitiateAuthCommand({
        AuthFlow:
          AuthFlowType.USER_PASSWORD_AUTH,

        ClientId:
          config.cognitoClientId,

        AuthParameters: {
          USERNAME: username,
          PASSWORD: password,
        },
      }),
    );

    if (!result.AuthenticationResult?.AccessToken) {
      throw new Error(
        "CognitoからAccess Tokenが返されませんでした",
      );
    }

    return {
      accessToken:
        result.AuthenticationResult.AccessToken,

      idToken:
        result.AuthenticationResult.IdToken,

      refreshToken:
        result.AuthenticationResult.RefreshToken,

      expiresIn:
        result.AuthenticationResult.ExpiresIn,
    };

  } finally {
    client.destroy();
  }
}