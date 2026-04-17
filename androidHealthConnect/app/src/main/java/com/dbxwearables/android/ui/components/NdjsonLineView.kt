package com.dbxwearables.android.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import com.dbxwearables.android.ui.theme.DbxGreen
import com.dbxwearables.android.ui.theme.DbxNavy
import com.dbxwearables.android.ui.theme.DbxTypography
import com.dbxwearables.android.ui.theme.DbxYellow
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject

@Composable
fun NdjsonLineView(
    lineNumber: Int,
    jsonLine: String,
    isExpanded: Boolean,
    onToggle: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(DbxNavy.copy(alpha = 0.6f))
            .clickable(onClick = onToggle)
            .padding(horizontal = 12.dp, vertical = 6.dp)
    ) {
        Row {
            Text(
                text = "${lineNumber}  ",
                style = DbxTypography.mono,
                color = Color.White.copy(alpha = 0.3f)
            )
            if (isExpanded) {
                Text(
                    text = prettyPrint(jsonLine),
                    style = DbxTypography.mono
                )
            } else {
                Text(
                    text = jsonLine.take(120) + if (jsonLine.length > 120) "..." else "",
                    style = DbxTypography.mono,
                    color = Color.White.copy(alpha = 0.8f),
                    maxLines = 1
                )
            }
        }
    }
}

private fun prettyPrint(json: String): AnnotatedString {
    return try {
        val obj = Json.parseToJsonElement(json)
        val pretty = Json { prettyPrint = true }.encodeToString(JsonObject.serializer(), obj as JsonObject)
        buildAnnotatedString {
            var i = 0
            while (i < pretty.length) {
                when {
                    pretty[i] == '"' && i > 0 && pretty[i - 1] != ':' && pretty.getOrNull(i - 1) != ' ' || (pretty[i] == '"' && pretty.indexOf(':', i).let { ci -> ci > 0 && ci < pretty.indexOf('"', i + 1) + 2 }) -> {
                        withStyle(SpanStyle(color = DbxGreen)) {
                            val end = pretty.indexOf('"', i + 1) + 1
                            append(pretty.substring(i, end))
                            i = end
                        }
                    }
                    else -> {
                        withStyle(SpanStyle(color = Color.White)) {
                            append(pretty[i])
                        }
                        i++
                    }
                }
            }
        }
    } catch (_: Exception) {
        buildAnnotatedString {
            withStyle(SpanStyle(color = Color.White)) { append(json) }
        }
    }
}
