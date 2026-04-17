package com.dbxwearables.android.domain.mapper

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class ExerciseTypeMapperTest {

    @Test
    fun `known exercise types map to snake_case names`() {
        assertEquals("running", ExerciseTypeMapper.fromCode(56))
        assertEquals("biking", ExerciseTypeMapper.fromCode(8))
        assertEquals("swimming_pool", ExerciseTypeMapper.fromCode(73))
        assertEquals("yoga", ExerciseTypeMapper.fromCode(80))
        assertEquals("hiking", ExerciseTypeMapper.fromCode(35))
    }

    @Test
    fun `unknown exercise type returns unknown_code`() {
        val result = ExerciseTypeMapper.fromCode(9999)
        assertTrue(result.startsWith("unknown_"), "Unknown codes should return 'unknown_<code>'")
        assertEquals("unknown_9999", result)
    }
}
