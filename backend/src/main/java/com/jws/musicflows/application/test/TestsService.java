package com.jws.musicflows.application.test;

import java.util.List;
import java.util.stream.Collectors;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.beans.BeanUtils;

import com.jws.musicflows.infrastructure.test.TestsEntity;
import com.jws.musicflows.infrastructure.test.TestsMapper;


@Service
public class TestsService {

    private final TestsMapper testsMapper;

    public TestsService(TestsMapper testsMapper) {
        this.testsMapper = testsMapper;
    }

    @Transactional(readOnly = true)
    public List<TestsDto> findAll() {
        
        return testsMapper.findAll().stream()
                .map(this::toDto)
                .collect(Collectors.toList());
    }

    @Transactional
    public TestsDto create(String name) {
        TestsEntity tests = new TestsEntity();
        tests.setName(name.trim());

        int insertedRows = testsMapper.insert(tests);

        if (insertedRows != 1 || tests.getId() == null) {
            throw new IllegalStateException("テストの登録に失敗しました");
        }

        TestsEntity createdTests =
            testsMapper.findById(tests.getId());

        if (createdTests == null) {
            throw new IllegalStateException(
                "登録したテストを取得できませんでした"
            );
        }

        TestsDto dto = this.toDto(createdTests);

        return dto;
    }

    private TestsDto toDto(TestsEntity entity) {
        var dto = new TestsDto();
        BeanUtils.copyProperties(entity, dto);
        return dto;
    }
}
