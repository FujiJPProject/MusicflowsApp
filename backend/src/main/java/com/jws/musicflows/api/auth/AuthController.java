package com.jws.musicflows.api.auth;

import java.util.LinkedHashMap;
import java.util.Map;

import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

/**
 * JWT認証状態確認用API。
 */
@RestController
@RequestMapping("/api/auth")
public class AuthController {

    @GetMapping("/me")
    public Map<String, Object> me(@AuthenticationPrincipal Jwt jwt) {
        if (jwt == null) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "JWT required");
        }

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("sub", jwt.getSubject());
        result.put("username", jwt.getClaimAsString("username"));
        result.put("tokenUse", jwt.getClaimAsString("token_use"));
        result.put("clientId", jwt.getClaimAsString("client_id"));
        result.put("issuer", jwt.getIssuer());
        return result;
    }
}
