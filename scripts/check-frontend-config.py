#!/usr/bin/env python3
"""公開するRuntime Configの入力検査。秘密情報を表示せず、設定不足時には失敗させる。"""

import argparse
import ipaddress
import json
import re
import sys
from pathlib import Path
from urllib.parse import urlsplit

STAGES = {"local", "dev", "production"}
LOCAL_ONLY = {"directApiBaseUrl", "cognitoEndpointUrl"}
PRIVATE_KEYS = {
    "accessToken", "idToken", "refreshToken", "clientSecret",
    "password", "secretAccessKey", "awsSecretAccessKey",
}


def require_string(config: dict, key: str) -> str:
    value = config.get(key)
    if not isinstance(value, str) or not value.strip() or value.strip() == "None":
        raise ValueError(f"必須文字列が不正です: {key}")
    if re.search(r"<[^>]+>|\$\{[^}]+\}", value):
        raise ValueError(f"置換されていないプレースホルダーがあります: {key}")
    return value.strip()


def validate_url(value: str, key: str, aws: bool) -> None:
    try:
        url = urlsplit(value)
        host = url.hostname
        _ = url.port  # ポートの構文異常を検出
    except ValueError as exc:
        raise ValueError(f"不正なURL: {key}") from exc

    if (
        url.scheme not in {"http", "https"}
        or not host
        or url.username is not None
        or url.password is not None
        or url.query
        or url.fragment
        or not url.netloc
    ):
        raise ValueError(f"不正なURL: {key}")
    if not aws:
        return
    if url.scheme != "https":
        raise ValueError(f"AWSではHTTPSが必須です: {key}")

    hostname = host.rstrip(".").lower()
    if (
        hostname == "localhost"
        or hostname.endswith(".localhost")
        or hostname.endswith(".local")
    ):
        raise ValueError(f"AWSではローカルホストを禁止します: {key}")
    try:
        addr = ipaddress.ip_address(hostname)
    except ValueError:
        addr = None
    if addr is not None and not addr.is_global:
        raise ValueError(f"AWSでは非公開IPを禁止します: {key}")


def validate(config: object, expected_stage: str) -> None:
    if not isinstance(config, dict):
        raise ValueError("Runtime ConfigはJSONオブジェクトが必要です")
    if any(k in config for k in PRIVATE_KEYS):
        raise ValueError("公開設定に秘密情報を含めないでください")

    stage = config.get("deploymentStage")
    if stage not in STAGES or stage != expected_stage:
        raise ValueError("deploymentStageが対象環境と一致しません")
    aws = stage != "local"

    url = require_string(config, "apiBaseUrl")
    validate_url(url, "apiBaseUrl", aws)
    for key in ("cognitoUserPoolId", "cognitoClientId", "awsRegion"):
        require_string(config, key)
    if not re.fullmatch(r"[a-z]{2}(-gov)?-[a-z]+-\d+", config["awsRegion"]):
        raise ValueError("awsRegionが不正です")

    mode = config.get("workerExecutionMode")
    if mode not in {"local", "lambda"} or (aws and mode != "lambda"):
        raise ValueError("workerExecutionModeが不正です")
    test_enabled = config.get("testPagesEnabled")
    if not isinstance(test_enabled, bool) or (stage == "production" and test_enabled):
        raise ValueError("testPagesEnabledが不正です")

    if aws:
        if any(k in config for k in LOCAL_ONLY):
            raise ValueError("AWS環境でローカル専用URLを公開できません")
        if "cognitoDomain" in config:
            validate_url(require_string(config, "cognitoDomain"), "cognitoDomain", True)
        if stage == "dev" and test_enabled and not config.get("cognitoDomain"):
            raise ValueError("devでテスト画面を使うにはCognito OAuthドメインが必要です")
    else:
        for key in LOCAL_ONLY:
            validate_url(require_string(config, key), key, False)
        if "cognitoDomain" in config:
            raise ValueError("local環境でAWS向けOAuthドメインを設定しないでください")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("path", type=Path)
    parser.add_argument("--stage", required=True, choices=sorted(STAGES))
    args = parser.parse_args()
    try:
        validate(json.loads(args.path.read_text(encoding="utf-8")), args.stage)
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        print(f"Runtime Config検証失敗: {exc}", file=sys.stderr)
        return 1
    print(f"Runtime Config検証成功: {args.stage}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
