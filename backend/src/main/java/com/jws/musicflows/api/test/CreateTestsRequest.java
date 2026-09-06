package com.jws.musicflows.api.test;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record CreateTestsRequest(
    @NotBlank(message = "プロジェクト名は必須です")
    @Size(max = 100, message = "プロジェクト名は100文字以内で入力してください")
    String name
) {

}
