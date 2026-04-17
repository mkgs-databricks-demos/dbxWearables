package com.dbxwearables.android.domain.mapper

import androidx.health.connect.client.records.ExerciseSessionRecord

/**
 * Maps Health Connect ExerciseSessionRecord exercise type integer constants
 * to human-readable snake_case strings for NDJSON serialization.
 */
object ExerciseTypeMapper {

    private val exerciseTypeMap: Map<Int, String> = mapOf(
        ExerciseSessionRecord.EXERCISE_TYPE_OTHER_WORKOUT to "other_workout",
        ExerciseSessionRecord.EXERCISE_TYPE_BADMINTON to "badminton",
        ExerciseSessionRecord.EXERCISE_TYPE_BASEBALL to "baseball",
        ExerciseSessionRecord.EXERCISE_TYPE_BASKETBALL to "basketball",
        ExerciseSessionRecord.EXERCISE_TYPE_BIKING to "biking",
        ExerciseSessionRecord.EXERCISE_TYPE_BOXING to "boxing",
        ExerciseSessionRecord.EXERCISE_TYPE_CALISTHENICS to "calisthenics",
        ExerciseSessionRecord.EXERCISE_TYPE_DANCING to "dancing",
        ExerciseSessionRecord.EXERCISE_TYPE_ELLIPTICAL to "elliptical",
        ExerciseSessionRecord.EXERCISE_TYPE_FOOTBALL_AMERICAN to "football_american",
        ExerciseSessionRecord.EXERCISE_TYPE_GOLF to "golf",
        ExerciseSessionRecord.EXERCISE_TYPE_HIGH_INTENSITY_INTERVAL_TRAINING to "high_intensity_interval_training",
        ExerciseSessionRecord.EXERCISE_TYPE_HIKING to "hiking",
        ExerciseSessionRecord.EXERCISE_TYPE_JUMPING_ROPE to "jumping_rope",
        ExerciseSessionRecord.EXERCISE_TYPE_MARTIAL_ARTS to "martial_arts",
        ExerciseSessionRecord.EXERCISE_TYPE_PILATES to "pilates",
        ExerciseSessionRecord.EXERCISE_TYPE_ROCK_CLIMBING to "rock_climbing",
        ExerciseSessionRecord.EXERCISE_TYPE_ROWING to "rowing",
        ExerciseSessionRecord.EXERCISE_TYPE_RUNNING to "running",
        ExerciseSessionRecord.EXERCISE_TYPE_SKATING to "skating",
        ExerciseSessionRecord.EXERCISE_TYPE_SKIING_CROSS_COUNTRY to "skiing_cross_country",
        ExerciseSessionRecord.EXERCISE_TYPE_SKIING_DOWNHILL to "skiing_downhill",
        ExerciseSessionRecord.EXERCISE_TYPE_SNOWBOARDING to "snowboarding",
        ExerciseSessionRecord.EXERCISE_TYPE_SOCCER to "soccer",
        ExerciseSessionRecord.EXERCISE_TYPE_STAIR_CLIMBING to "stair_climbing",
        ExerciseSessionRecord.EXERCISE_TYPE_STRENGTH_TRAINING to "strength_training",
        ExerciseSessionRecord.EXERCISE_TYPE_SURFING to "surfing",
        ExerciseSessionRecord.EXERCISE_TYPE_SWIMMING_OPEN_WATER to "swimming_open_water",
        ExerciseSessionRecord.EXERCISE_TYPE_SWIMMING_POOL to "swimming_pool",
        ExerciseSessionRecord.EXERCISE_TYPE_TABLE_TENNIS to "table_tennis",
        ExerciseSessionRecord.EXERCISE_TYPE_TENNIS to "tennis",
        ExerciseSessionRecord.EXERCISE_TYPE_VOLLEYBALL to "volleyball",
        ExerciseSessionRecord.EXERCISE_TYPE_WALKING to "walking",
        ExerciseSessionRecord.EXERCISE_TYPE_YOGA to "yoga"
    )

    /**
     * Returns the snake_case name for the given exercise type code,
     * or "unknown_$code" if the code is not recognized.
     */
    fun fromCode(code: Int): String {
        return exerciseTypeMap[code] ?: "unknown_$code"
    }
}
