package com.jws.musicflows.api.auth;

import java.util.LinkedHashMap;
import java.util.Map;

import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * JWT認証状態確認用API。
 */
@RestController
@RequestMapping("/api/auth")
public class AuthController {

    /**
     * Spring Securityで認証されたユーザー情報を返す。
     */
    @GetMapping("/me")
    public Map<String, Object> me(
            @AuthenticationPrincipal Jwt jwt
    ) {

        Map<String, Object> result =
                new LinkedHashMap<>();

        result.put(
            "sub",
            jwt.getSubject()
        );

        result.put(
            "username",
            jwt.getClaimAsString("username")
        );

        result.put(
            "tokenUse",
            jwt.getClaimAsString("token_use")
        );

        result.put(
            "clientId",
            jwt.getClaimAsString("client_id")
        );

        result.put(
            "issuer",
            jwt.getIssuer()
        );

        return result;
    }
}