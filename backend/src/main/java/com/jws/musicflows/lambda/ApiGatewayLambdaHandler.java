package com.jws.musicflows.lambda;

import com.amazonaws.serverless.exceptions.ContainerInitializationException;
import com.amazonaws.serverless.proxy.model.AwsProxyRequest;
import com.amazonaws.serverless.proxy.model.AwsProxyResponse;
import com.amazonaws.serverless.proxy.spring.SpringBootLambdaContainerHandler;
import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.jws.musicflows.MusicflowsApplication;


  /**
 * API Gateway から呼び出される AWS Lambda ハンドラー。
 *
 * <p>
 * AWS Lambda 上で Spring Boot アプリケーションを実行するためのエントリーポイントです。
 * API Gateway から受け取ったリクエストを Spring Boot の Controller に転送し、
 * Controller の処理結果を API Gateway 用のレスポンスとして返却します。
 * </p>
 *
 * <pre>
 * API Gateway のリクエスト
 *        ↓
 * AwsProxyRequest  
 *        ↓
 * Spring Boot Controller
 *        ↓
 * AwsProxyResponse
 *        ↓
 * API Gateway のレスポンス
 * </pre>
 */
public class ApiGatewayLambdaHandler implements RequestHandler<AwsProxyRequest, AwsProxyResponse> {

    /**
     * Spring Boot アプリケーションを Lambda 上で実行するためのコンテナハンドラー。
     *
     * <p>
     * static フィールドとして保持することで、Lambda の実行環境が再利用される場合に
     * Spring Boot の初期化済みコンテキストを再利用できます。
     * </p>
     */
    private static final SpringBootLambdaContainerHandler<AwsProxyRequest, AwsProxyResponse> Handler;

    /**
     * Lambda ハンドラーの初期化処理。
     *
     * <p>
     * クラスロード時に一度だけ実行され、Spring Boot アプリケーションを
     * Lambda 用のハンドラーとして初期化します。
     * 主にコールドスタート時に実行されます。
     * </p>
     */
    static {
        try {
            Handler = SpringBootLambdaContainerHandler.getAwsProxyHandler(
                MusicflowsApplication.class);

        } catch (ContainerInitializationException e) {
            throw new RuntimeException("Spring Boot Lambda initialization failed", e);
        }
    }

    @Override
    public AwsProxyResponse handleRequest(
            AwsProxyRequest request,
            Context context
    ) {

        /*
         * GET / POST / PUT / DELETEなどを
         * Spring Bootへ委譲する。
         *
         * ブラウザのCORS preflightは
         * Floci自身のGlobal CORSで処理する。
         */
        return Handler.proxy(request, context);
    }
}