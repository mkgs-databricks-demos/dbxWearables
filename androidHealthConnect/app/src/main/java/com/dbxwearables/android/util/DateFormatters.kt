package com.dbxwearables.android.util

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

object DateFormatters {

    private val dateFormatter: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd")

    fun formatInstant(instant: Instant): String {
        return DateTimeFormatter.ISO_INSTANT.format(instant)
    }

    fun formatZoneOffset(offset: ZoneOffset?): String? {
        return offset?.toString()
    }

    fun formatDate(date: LocalDate): String {
        return date.format(dateFormatter)
    }
}
