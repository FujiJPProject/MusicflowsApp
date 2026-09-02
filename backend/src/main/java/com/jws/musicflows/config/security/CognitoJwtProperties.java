package com.jws.musicflows.config.security;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Cognitoが発行したJWTを検証するための設定。
 */
@ConfigurationProperties(
        prefix = "app.security.cognito"
)
public record CognitoJwtProperties(

        // JWTのiss claimとして期待する値
        String issuerUri,

        // JWTの署名検証に使用するJWKS URL
        String jwkSetUri,

        // JWTを発行したCognito App Client ID
        String clientId
) {
}