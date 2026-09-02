package com.jws.musicflows.api.testjob;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record CreateTestJobRequest(
        @NotBlank
        @Size(max = 4096)
        String payload

) {
}