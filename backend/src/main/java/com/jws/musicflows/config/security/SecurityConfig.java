package com.jws.musicflows.config.security;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.core.env.Environment;
import org.springframework.http.HttpMethod;
import org.springframework.security.authentication.AuthenticationTrustResolver;
import org.springframework.security.authentication.AuthenticationTrustResolverImpl;
import org.springframework.security.authorization.AuthorizationDecision;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.oauth2.core.DelegatingOAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2TokenValidator;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtClaimValidator;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtValidators;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.security.web.SecurityFilterChain;

@Configuration
@EnableConfigurationProperties(
        CognitoJwtProperties.class
)
public class SecurityConfig {

    /**
     * Lambda環境用SecurityFilterChain。
     *
     * SPRING_PROFILES_ACTIVE=lambda の場合だけ有効。
     * @param http HttpSecurity
     * @param environment Spring Boot の実行環境情報
     */
    @Bean
    @Profile("lambda")
    SecurityFilterChain lambdaSecurityFilterChain(
            HttpSecurity http,
            Environment environment
    ) throws Exception {

        // Flociでは疎通確認用APIを有効にするかどうかを環境変数で制御する。
        boolean testApisEnabled = environment.getProperty(
                "app.features.test-apis-enabled",
                Boolean.class,
                false
        );

        // 認証済みかどうかを判定するためのヘルパー
        AuthenticationTrustResolver trustResolver =
                    new AuthenticationTrustResolverImpl();

        http
            /*
             * Bearer Token APIなので
             * HTTP Sessionは使用しない。
             */
            .sessionManagement(session ->
                session.sessionCreationPolicy(
                    SessionCreationPolicy.STATELESS
                )
            )

            /*
             * Cookie認証を使用しないためCSRF無効。
             */
            .csrf(AbstractHttpConfigurer::disable)

            /*
             * WebCorsConfigを利用。
             */
            .cors(Customizer.withDefaults())

            .authorizeHttpRequests(auth -> auth

                /*
                 * preflightは認証不要。
                 *
                 * API Gateway経由ではFloci Global CORSが
                 * 先に処理する。
                 */
                .requestMatchers(HttpMethod.OPTIONS,"/**").permitAll()

                // ヘルスチェックは公開。
                .requestMatchers("/api/health").permitAll()

                /*
                 * 疎通確認専用API。
                 *
                 * Flociでは許可し、実AWSでは既定で拒否。
                 * 許可した場合もJWT認証は必須。
                 */
                .requestMatchers(
                        "/api/tests",
                        "/api/tests/**",
                        "/api/auth/**",
                        "/api/test-jobs",
                        "/api/test-jobs/**"
                )
                .access((authentication, context) ->
                        new AuthorizationDecision(
                            testApisEnabled
                            && trustResolver.isAuthenticated(
                                authentication.get()
                        )
                )
        )

                /*
                 * 第2段階では未定義APIも
                 * 原則認証必須にしておく。
                 */
                .anyRequest().authenticated()
            )

            /*
             * Authorization:
             * Bearer <Cognito Access Token>
             */
            .oauth2ResourceServer(oauth2 ->
                oauth2.jwt(Customizer.withDefaults())
            );

        return http.build();
    }


    /**
     * Spring Boot直接接続用。
     *
     * SPRING_PROFILES_ACTIVE=local の場合だけ有効。
     *
     * 第1段階のApp.tsxによる疎通確認を維持するため、
     * localでは認証なしで利用できる。
     */
    @Bean
    @Profile("local")
    SecurityFilterChain localSecurityFilterChain(
            HttpSecurity http
    ) throws Exception {

        http
            .csrf(AbstractHttpConfigurer::disable)
            .cors(Customizer.withDefaults())
            .authorizeHttpRequests(auth ->
                auth.anyRequest().permitAll()
            );

        return http.build();
    }


    /**
     * Cognito JWT検証。
     *
     * Lambda環境でのみ必要。
     */
    @Bean
    @Profile("lambda")
    JwtDecoder jwtDecoder(
            CognitoJwtProperties properties
    ) {

        /*
         * Cognito JWKSから公開鍵を取得して
         * RS256署名を検証する。
         */
        NimbusJwtDecoder decoder =
            NimbusJwtDecoder
                .withJwkSetUri(
                    properties.jwkSetUri()
                )
                .build();

        /*
         * issuer / exp / nbf等の標準検証。
         */
        OAuth2TokenValidator<Jwt> issuerValidator =
            JwtValidators.createDefaultWithIssuer(
                properties.issuerUri()
            );

        /*
         * APIではAccess Tokenだけ許可する。
         *
         * ID Token:
         * token_use=id
         *
         * Access Token:
         * token_use=access
         */
        OAuth2TokenValidator<Jwt> tokenUseValidator =
            new JwtClaimValidator<>(
                "token_use",
                "access"::equals
            );

        /*
         * このアプリのCognito App Clientから
         * 発行されたTokenだけ許可する。
         */
        OAuth2TokenValidator<Jwt> clientIdValidator =
            new JwtClaimValidator<>(
                "client_id",
                properties.clientId()::equals
            );

        decoder.setJwtValidator(
            new DelegatingOAuth2TokenValidator<>(
                issuerValidator,
                tokenUseValidator,
                clientIdValidator
            )
        );

        return decoder;
    }
}