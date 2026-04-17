package com.dbxwearables.android.util

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

object NDJSONSerializer {

    private val json = Json {
        encodeDefaults = false
        explicitNulls = false
    }

    inline fun <reified T> encode(items: List<T>): ByteArray {
        if (items.isEmpty()) return ByteArray(0)
        return encodeToString(items).toByteArray(Charsets.UTF_8)
    }

    inline fun <reified T> encodeToString(items: List<T>): String {
        if (items.isEmpty()) return ""
        return items.joinToString("\n") { item ->
            val element = json.parseToJsonElement(json.encodeToString(item))
            val sorted = sortJsonElement(element)
            json.encodeToString(JsonElement.serializer(), sorted)
        }
    }

    @PublishedApi
    internal fun sortJsonElement(element: JsonElement): JsonElement {
        return when (element) {
            is JsonObject -> {
                val sortedEntries = element.entries
                    .sortedBy { it.key }
                    .associate { (key, value) -> key to sortJsonElement(value) }
                JsonObject(sortedEntries)
            }
            is JsonArray -> {
                JsonArray(element.map { sortJsonElement(it) })
            }
            is JsonPrimitive -> element
        }
    }
}
