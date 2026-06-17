package com.jws.musicflows.lambda;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

import com.amazonaws.serverless.exceptions.ContainerInitializationException;
import com.amazonaws.serverless.proxy.model.AwsProxyRequest;
import com.amazonaws.serverless.proxy.model.AwsProxyResponse;
import com.amazonaws.serverless.proxy.spring.SpringBootLambdaContainerHandler;
import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestStreamHandler;
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
public class ApiGatewayLambdaHandler implements RequestStreamHandler {

    /**
     * Spring Boot アプリケーションを Lambda 上で実行するためのコンテナハンドラー。
     *
     * <p>
     * static フィールドとして保持することで、Lambda の実行環境が再利用される場合に
     * Spring Boot の初期化済みコンテキストを再利用できます。
     * </p>
     */
    private static final SpringBootLambdaContainerHandler<AwsProxyRequest, AwsProxyResponse> handler;

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
            handler = SpringBootLambdaContainerHandler.getAwsProxyHandler(MusicflowsApplication.class);
        } catch (ContainerInitializationException e) {
            throw new RuntimeException("Spring Boot Lambda initialization failed", e);
        }
    }

    /**
     * Lambda 関数に渡されたリクエストを処理します。
     *
     * <p>
     * API Gateway から渡された入力ストリームを Spring Boot 側へ転送し、
     * Spring Boot の処理結果を出力ストリームへ書き込みます。
     * </p>
     *
     * @param inputStream  API Gateway から渡されるリクエストの入力ストリーム
     * @param outputStream API Gateway へ返却するレスポンスの出力ストリーム
     * @param context      Lambda の実行コンテキスト
     * @throws IOException 入出力処理でエラーが発生した場合
     */
    @Override
    public void handleRequest(InputStream inputStream, OutputStream outputStream, Context context) throws IOException {
        handler.proxyStream(inputStream, outputStream, context);
    }
}