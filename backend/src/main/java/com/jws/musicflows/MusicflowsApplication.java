package com.jws.musicflows;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Musicflows アプリケーションのエントリーポイント。
 *
 * <p>
 * Spring Boot アプリケーションを起動するためのクラスです。
 * AWS Lambda 上で実行される際には、lambda/ApiGatewayLambdaHandler クラスから呼び出されます。
 * </p>
 */
@SpringBootApplication
public class MusicflowsApplication {

	/**
	 * アプリケーションのメインメソッド。
	 *
	 * <p>
	 * Spring Boot アプリケーションを起動します。
	 * AWS Lambda 上で実行される際には、lambda/ApiGatewayLambdaHandler クラスから呼び出されます。
	 * </p>
	 *
	 * @param args コマンドライン引数
	 */
	public static void main(String[] args) {
		SpringApplication.run(MusicflowsApplication.class, args);
	}

}
