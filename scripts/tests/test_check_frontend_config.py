"""Runtime Configのstage・localhost拒否・公開用設定を検証するテスト。"""
import importlib.util
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).resolve().parents[1] / "check-frontend-config.py"
SPEC = importlib.util.spec_from_file_location("check_frontend_config", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


def local_config():
    return {
        "deploymentStage": "local",
        "apiBaseUrl": "http://localhost:4567/restapis/api/local/_user_request_",
        "directApiBaseUrl": "http://localhost:8081",
        "cognitoUserPoolId": "local_pool",
        "cognitoClientId": "local_client",
        "awsRegion": "ap-northeast-1",
        "cognitoEndpointUrl": "http://localhost:4567",
        "workerExecutionMode": "lambda",
        "testPagesEnabled": True,
    }


def aws_config():
    return {
        "deploymentStage": "dev",
        "apiBaseUrl": "https://api.example.com/dev",
        "cognitoUserPoolId": "ap-northeast-1_EXAMPLE",
        "cognitoClientId": "web-client",
        "awsRegion": "ap-northeast-1",
        "cognitoDomain": "https://example.auth.ap-northeast-1.amazoncognito.com",
        "workerExecutionMode": "lambda",
        "testPagesEnabled": True,
    }


class RuntimeConfigTest(unittest.TestCase):
    def test_valid_local(self):
        MODULE.validate(local_config(), "local")

    def test_valid_dev(self):
        MODULE.validate(aws_config(), "dev")

    def test_wrong_stage_fails(self):
        with self.assertRaises(ValueError):
            MODULE.validate(local_config(), "dev")

    def test_aws_localhost_fails(self):
        config = aws_config()
        config["apiBaseUrl"] = "https://localhost:8080"
        with self.assertRaises(ValueError):
            MODULE.validate(config, "dev")

    def test_aws_private_ip_fails(self):
        config = aws_config()
        config["apiBaseUrl"] = "https://127.0.0.1/api"
        with self.assertRaises(ValueError):
            MODULE.validate(config, "dev")

    def test_aws_http_fails(self):
        config = aws_config()
        config["apiBaseUrl"] = "http://api.example.com/dev"
        with self.assertRaises(ValueError):
            MODULE.validate(config, "dev")

    def test_aws_local_only_field_fails(self):
        config = aws_config()
        config["directApiBaseUrl"] = "http://localhost:8080"
        with self.assertRaises(ValueError):
            MODULE.validate(config, "dev")

    def test_production_test_pages_fails(self):
        config = aws_config()
        config["deploymentStage"] = "production"
        with self.assertRaises(ValueError):
            MODULE.validate(config, "production")

    def test_dev_test_pages_requires_cognito_domain(self):
        config = aws_config()
        del config["cognitoDomain"]
        with self.assertRaises(ValueError):
            MODULE.validate(config, "dev")

    def test_public_secret_fields_fails(self):
        config = aws_config()
        config["password"] = "must-never-be-public"
        with self.assertRaises(ValueError):
            MODULE.validate(config, "dev")

    def test_unexpanded_placeholder_fails(self):
        config = aws_config()
        config["cognitoClientId"] = "${CLIENT_ID}"
        with self.assertRaises(ValueError):
            MODULE.validate(config, "dev")


if __name__ == "__main__":
    unittest.main()
