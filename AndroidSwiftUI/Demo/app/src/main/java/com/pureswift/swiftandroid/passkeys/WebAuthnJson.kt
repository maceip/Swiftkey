package com.pureswift.swiftandroid.passkeys

import org.json.JSONArray
import org.json.JSONObject

/** Strict JSON admission before using org.json, whose Android parser is lenient. */
internal object WebAuthnJson {
    const val MAX_BYTES = 65_536

    fun objectValue(input: String): JSONObject {
        if (input.toByteArray(Charsets.UTF_8).size > MAX_BYTES) invalid("Request is too large.")
        return Parser(input).parse()
    }

    private fun invalid(message: String): Nothing = throw WebAuthnException("invalidRequest", message)

    private class Parser(private val source: String) {
        private var position = 0
        private var values = 0

        fun parse(): JSONObject {
            val result = value(0)
            whitespace()
            if (position != source.length || result !is JSONObject) invalid("Expected one JSON object.")
            return result
        }

        private fun value(depth: Int): Any {
            if (depth > 16 || ++values > 4096) invalid("Request nesting or item count is too large.")
            whitespace()
            return when (peek()) {
                '{' -> objectValue(depth + 1)
                '[' -> arrayValue(depth + 1)
                '"' -> stringValue()
                't' -> literal("true", true)
                'f' -> literal("false", false)
                'n' -> literal("null", JSONObject.NULL)
                '-', in '0'..'9' -> numberValue()
                else -> invalid("Invalid JSON value.")
            }
        }

        private fun objectValue(depth: Int): JSONObject {
            position++
            val objectValue = JSONObject()
            val keys = mutableSetOf<String>()
            whitespace()
            if (take('}')) return objectValue
            while (true) {
                whitespace()
                if (peek() != '"') invalid("JSON object keys must be quoted.")
                val key = stringValue()
                if (key.length > 256 || !keys.add(key)) invalid("Duplicate or oversized JSON object key.")
                whitespace()
                if (!take(':')) invalid("Missing JSON colon.")
                objectValue.put(key, value(depth))
                whitespace()
                if (take('}')) return objectValue
                if (!take(',')) invalid("Missing JSON object separator.")
            }
        }

        private fun arrayValue(depth: Int): JSONArray {
            position++
            val array = JSONArray()
            whitespace()
            if (take(']')) return array
            while (true) {
                if (array.length() >= 128) invalid("Too many JSON array entries.")
                array.put(value(depth))
                whitespace()
                if (take(']')) return array
                if (!take(',')) invalid("Missing JSON array separator.")
            }
        }

        private fun stringValue(): String {
            position++ // Opening quote was checked by the caller.
            val result = StringBuilder()
            while (position < source.length) {
                val ch = source[position++]
                when {
                    ch == '"' -> {
                        val text = result.toString()
                        var index = 0
                        while (index < text.length) {
                            val current = text[index++]
                            if (current.isHighSurrogate()) {
                                if (index >= text.length || !text[index++].isLowSurrogate()) invalid("Invalid Unicode string.")
                            } else if (current.isLowSurrogate()) invalid("Invalid Unicode string.")
                        }
                        return text
                    }
                    ch == '\\' -> {
                        if (position == source.length) invalid("Incomplete JSON escape.")
                        when (val escaped = source[position++]) {
                            '"', '\\', '/' -> result.append(escaped)
                            'b' -> result.append('\b')
                            'f' -> result.append('\u000c')
                            'n' -> result.append('\n')
                            'r' -> result.append('\r')
                            't' -> result.append('\t')
                            'u' -> {
                                if (position + 4 > source.length) invalid("Incomplete Unicode escape.")
                                val digits = source.substring(position, position + 4)
                                if (digits.any { it !in "0123456789abcdefABCDEF" }) invalid("Invalid Unicode escape.")
                                result.append(digits.toInt(16).toChar()); position += 4
                            }
                            else -> invalid("Invalid JSON escape.")
                        }
                    }
                    ch.code < 0x20 -> invalid("Unescaped JSON control character.")
                    else -> result.append(ch)
                }
                if (result.length > 8192) invalid("JSON string is too large.")
            }
            invalid("Unterminated JSON string.")
        }

        private fun numberValue(): Number {
            val start = position
            take('-')
            if (!take('0')) {
                if (peek() !in '1'..'9') invalid("Invalid JSON number.")
                while (peek() in '0'..'9') position++
            }
            if (take('.')) {
                if (peek() !in '0'..'9') invalid("Invalid JSON fraction.")
                while (peek() in '0'..'9') position++
            }
            if (peek() == 'e' || peek() == 'E') {
                position++
                if (peek() == '+' || peek() == '-') position++
                if (peek() !in '0'..'9') invalid("Invalid JSON exponent.")
                while (peek() in '0'..'9') position++
            }
            val number = source.substring(start, position)
            if (number.length > 64) invalid("JSON number is too large.")
            return if (number.none { it == '.' || it == 'e' || it == 'E' }) {
                number.toLongOrNull() ?: invalid("JSON integer is out of range.")
            } else {
                number.toDoubleOrNull()?.takeIf { it.isFinite() } ?: invalid("JSON number is out of range.")
            }
        }

        private fun literal(expected: String, result: Any): Any {
            if (!source.startsWith(expected, position)) invalid("Invalid JSON literal.")
            position += expected.length
            return result
        }

        private fun whitespace() { while (peek() in listOf(' ', '\t', '\r', '\n')) position++ }
        private fun peek(): Char = source.getOrNull(position) ?: '\u0000'
        private fun take(ch: Char): Boolean = if (peek() == ch) { position++; true } else false
    }
}
