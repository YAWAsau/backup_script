package com.xayah.dex

import java.io.IOException
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Locale
import java.util.concurrent.atomic.AtomicLong

/** RFC 7616 qop=auth; auth-int needs a replayable entity and is deliberately rejected. */
internal class HttpDigest private constructor(private val fields: Map<String, String>) {
    private val sequence = AtomicLong()
    private val algorithm = fields["algorithm"] ?: "MD5"
    private val hashAlgorithm = when (algorithm.uppercase(Locale.US).removeSuffix("-SESS")) {
        "MD5" -> "MD5"
        "SHA-256" -> "SHA-256"
        else -> throw IOException("HTTP_DIGEST_UNSUPPORTED_ALGORITHM")
    }
    private val charset = when (fields["charset"]?.uppercase(Locale.US)) {
        null -> StandardCharsets.ISO_8859_1
        "UTF-8" -> StandardCharsets.UTF_8
        else -> throw IOException("HTTP_DIGEST_UNSUPPORTED_CHARSET")
    }
    private val qop = fields["qop"]?.let {
        if (it.split(',').none { q -> q.trim().equals("auth", true) }) throw IOException("HTTP_DIGEST_AUTH_INT_UNSUPPORTED")
        "auth"
    }

    fun authorization(method: String, uri: String, user: String, password: String): String {
        fun hash(text: String) = MessageDigest.getInstance(hashAlgorithm).digest(text.toByteArray(charset)).joinToString("") { "%02x".format(it.toInt() and 255) }
        fun quoted(text: String): String {
            if (text.any { it == '\r' || it == '\n' || it.code < 32 }) throw IOException("HTTP_DIGEST_INVALID_FIELD")
            return "\"" + text.replace("\\", "\\\\").replace("\"", "\\\"") + "\""
        }
        val realm = fields.getValue("realm")
        val nonce = fields.getValue("nonce")
        val cnonce = ByteArray(16).also { SecureRandom().nextBytes(it) }.joinToString("") { "%02x".format(it.toInt() and 255) }
        val nc = sequence.incrementAndGet().let { if (it > 0xffffffffL) throw IOException("HTTP_DIGEST_NONCE_EXHAUSTED") else "%08x".format(it) }
        val initial = hash("$user:$realm:$password")
        val session = algorithm.endsWith("-sess", true)
        val ha1 = if (session) hash("$initial:$nonce:$cnonce") else initial
        val ha2 = hash("$method:$uri")
        val response = if (qop == null) hash("$ha1:$nonce:$ha2") else hash("$ha1:$nonce:$nc:$cnonce:auth:$ha2")
        val userhash = fields["userhash"].equals("true", true)
        val values = mutableListOf("username=" + quoted(if (userhash) hash("$user:$realm") else user), "realm=" + quoted(realm), "nonce=" + quoted(nonce), "uri=" + quoted(uri), "response=" + quoted(response), "algorithm=$algorithm")
        fields["opaque"]?.let { values.add("opaque=" + quoted(it)) }
        if (qop != null) values.add("qop=auth, nc=$nc")
        if (qop != null || session) values.add("cnonce=" + quoted(cnonce))
        if (userhash) values.add("userhash=true")
        return "Digest " + values.joinToString(", ")
    }

    companion object {
        fun from(headers: Map<String, List<String>>): HttpDigest? {
            val challenges = headers.entries.filter { it.key.equals("www-authenticate", true) }.flatMap { it.value }
            var unsupported: IOException? = null
            // Split only at authentication schemes, never at commas inside quoted qop/realm values.
            val scheme = Regex("(?i)(?:^|,)\\s*(Digest|Basic|Bearer)\\s+(?=[A-Za-z])")
            for (line in challenges) {
                var quoted = false
                var escaped = false
                val outside = BooleanArray(line.length + 1)
                for (i in line.indices) {
                    outside[i] = !quoted
                    if (escaped) escaped = false
                    else if (line[i] == '\\' && quoted) escaped = true
                    else if (line[i] == '"') quoted = !quoted
                }
                val starts = scheme.findAll(line).filter { outside[it.range.first] }.toList()
                for ((index, match) in starts.withIndex()) {
                    if (!match.groupValues[1].equals("Digest", true)) continue
                    val body = line.substring(match.range.last + 1, starts.getOrNull(index + 1)?.range?.first ?: line.length)
                    try { return HttpDigest(parse(body)) } catch (e: IOException) { unsupported = e }
                }
            }
            if (unsupported != null) throw unsupported
            return null
        }

        private fun parse(body: String): Map<String, String> {
            val result = linkedMapOf<String, String>()
            var i = 0
            while (i < body.length) {
                while (i < body.length && (body[i].isWhitespace() || body[i] == ',')) i++
                if (i == body.length) break
                val begin = i
                while (i < body.length && (body[i].isLetterOrDigit() || body[i] in "_-")) i++
                val name = body.substring(begin, i).lowercase(Locale.US)
                while (i < body.length && body[i].isWhitespace()) i++
                if (name.isEmpty() || i >= body.length || body[i++] != '=') throw IOException("HTTP_DIGEST_BAD_CHALLENGE")
                while (i < body.length && body[i].isWhitespace()) i++
                val value = StringBuilder()
                val isQuoted = i < body.length && body[i] == '"'
                if (isQuoted) {
                    i++
                    var closed = false
                    while (i < body.length) {
                        val ch = body[i++]
                        if (ch == '"') { closed = true; break }
                        if (ch == '\\') { if (i >= body.length) throw IOException("HTTP_DIGEST_BAD_ESCAPE"); value.append(body[i++]) } else value.append(ch)
                    }
                    if (!closed) throw IOException("HTTP_DIGEST_UNCLOSED_QUOTE")
                } else {
                    while (i < body.length && body[i] != ',') value.append(body[i++])
                }
                if (result.put(name, if (isQuoted) value.toString() else value.toString().trim()) != null) throw IOException("HTTP_DIGEST_DUPLICATE_FIELD")
            }
            if (result["realm"] == null || result["nonce"].isNullOrEmpty()) throw IOException("HTTP_DIGEST_MISSING_FIELD")
            return result
        }
    }
}
