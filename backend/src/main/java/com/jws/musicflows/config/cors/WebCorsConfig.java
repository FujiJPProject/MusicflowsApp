package com.jws.musicflows.config.cors;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Bean;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;
import org.springframework.web.filter.CorsFilter;

import java.util.List;

/**
 * CORS 設定クラス。
 */
@Configuration
public class WebCorsConfig {

    /**
     * CORS フィルターを設定します。
     *
     * @param allowedOrigin 許可するオリジン
     * @return CORS フィルター
     */
    @Bean
    public CorsFilter corsFilter(
            @Value("${app.cors.allowed-origin}") String allowedOrigin
    ) {

        CorsConfiguration configuration =
                new CorsConfiguration();

        // 許可するオリジンを設定。
        configuration.setAllowedOrigins(
                List.of(allowedOrigin)
        );

        // 許可する HTTP メソッドを設定。
        configuration.setAllowedMethods(
                List.of(
                        "GET",
                        "POST",
                        "PUT",
                        "DELETE",
                        "OPTIONS"
                )
        );

        // 許可する HTTP ヘッダーを設定。
        configuration.setAllowedHeaders(
                List.of("*")
        );

        // プリフライトリクエストのキャッシュ時間を設定。
        configuration.setMaxAge(3600L);

        // 認証情報を含むリクエストを許可するかどうかを設定。
        UrlBasedCorsConfigurationSource source =
                new UrlBasedCorsConfigurationSource();

        source.registerCorsConfiguration(
                "/api/**",
                configuration
        );

        return new CorsFilter(source);
    }
}