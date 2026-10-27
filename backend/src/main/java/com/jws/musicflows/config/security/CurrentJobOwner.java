package com.jws.musicflows.config.security;

import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;
import org.springframework.http.HttpStatus;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ResponseStatusException;

/**
 * 現在のジョブ所有者を取得するコンポーネント。
 *
 */
@Component
public class CurrentJobOwner {

    /** Spring Boot の実行環境情報。 */
    private final Environment environment;

    /**
     * コンストラクタ
     *
     * @param environment Spring Boot の実行環境情報
     */
    public CurrentJobOwner(Environment environment) {
        this.environment = environment;
    }

    /**
     * 現在のジョブ所有者を取得します。
     *
     * localプロファイルの時は固定の開発用識別子を返し、
     * lambdaプロファイルの時はSpring Securityが検証したJWTのsubクレームを返します。
     * 
     *
     * @param jwt Spring Security が検証した JWT
     * @return ジョブ所有者の識別子
     * @throws ResponseStatusException lambda プロファイルで認証情報がない場合
     * @throws IllegalStateException サポート対象外のプロファイルの場合
     */
    public String requireOwner(Jwt jwt) {

        /*
         * AWS Lambda / Floci Lambda 環境では、
         * Spring Security が検証済みの JWT を使用する。
         */
        if (environment.acceptsProfiles(Profiles.of("lambda"))) {
            if (jwt == null || jwt.getSubject() == null || jwt.getSubject().isBlank()) {
                throw new ResponseStatusException(
                        HttpStatus.UNAUTHORIZED,
                        "Authentication is required"
                );
            }

            return jwt.getSubject();
        }

        /*
         * Spring Boot を直接起動する local 環境だけ、
         * 固定の開発用識別子を許可する。
         */
        if (environment.acceptsProfiles(Profiles.of("local"))) {
            return "local";
        }

        /* 想定外のプロファイルではジョブ操作を許可しない。 */
        throw new IllegalStateException("Unsupported authentication profile");
    }
}