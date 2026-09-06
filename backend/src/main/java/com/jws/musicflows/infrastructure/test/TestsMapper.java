package com.jws.musicflows.infrastructure.test;

import java.util.List;

import org.apache.ibatis.annotations.Mapper;

/**
 * 接続確認用Mapper インターフェース。
 */
@Mapper
public interface TestsMapper {

    /**
     * すべての接続確認用エンティティを取得します。
     *
     * @return 接続確認用エンティティのリスト
     */
    List<TestsEntity> findAll();

    /**
     * ID で接続確認用エンティティを取得します。
     *
     * @param id エンティティの ID
     * @return 接続確認用エンティティ
     */
    TestsEntity findById(Long id);

    /**
     * 接続確認用エンティティを登録します。
     *
     * @param tests 登録するエンティティ
     * @return 登録された行数
     */
    int insert(TestsEntity tests);
}