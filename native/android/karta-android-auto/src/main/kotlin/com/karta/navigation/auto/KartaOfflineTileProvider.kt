package com.karta.navigation.auto

import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.RandomAccessFile
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Generates Karta Dark v1 MapLibre Style JSON (`#0D0F12`, `#181C22`, `#5B9A94`)
 * and hosts a localhost-only (`127.0.0.1`) offline HTTP Range proxy for downloaded
 * regional `.pmtiles` archives (`my-peninsular-*`, `my-borneo`, `sg`, `bn`) so
 * Android Auto renders vector maps reliably inside tunnels and cross-border dead zones
 * with zero external network calls.
 */
class KartaOfflineTileProvider {
    private val running = AtomicBoolean(false)
    private val executor = Executors.newCachedThreadPool()
    private var serverSocket: ServerSocket? = null
    @Volatile
    private var activeOfflineFile: File? = null

    val localPort: Int
        get() = serverSocket?.localPort ?: -1

    fun startIfNeeded(localPmtilesFile: File?) {
        activeOfflineFile = localPmtilesFile?.takeIf { it.exists() && it.isFile }
        if (activeOfflineFile == null || running.get()) return
        try {
            val socket = ServerSocket(0, 16, InetAddress.getByName("127.0.0.1"))
            serverSocket = socket
            running.set(true)
            executor.execute { acceptLoop(socket) }
        } catch (_: Exception) {
            running.set(false)
        }
    }

    fun stop() {
        running.set(false)
        try {
            serverSocket?.close()
        } catch (_: Exception) {
        }
        serverSocket = null
        activeOfflineFile = null
    }

    /**
     * Builds Karta dual-lighting MapLibre Style v8 JSON (`Obsidian Night` `#0D0F12` or
     * `Tropical Daylight` `#F5F2EB`) synced to the vehicle's headlight/dimmer sensor and bound to:
     * 1. Verified local offline `.pmtiles` archive via `pmtiles://http://127.0.0.1:<port>/offline.pmtiles`
     * 2. Live `go-pmtiles` TileJSON / PMTiles endpoint (`config.activePmtilesUrl`).
     */
    fun buildStyleJson(
        config: KartaAutoOfflineConfig,
        enable3DBuildings: Boolean,
        isDarkMode: Boolean = true,
    ): String {
        val localCandidate = config.downloadedRegions
            .map { File(it.localPmtilesPath) }
            .firstOrNull { it.exists() && it.isFile }

        if (config.offlineModeEnabled && localCandidate != null) {
            startIfNeeded(localCandidate)
        }

        val sourceUrl = if (config.offlineModeEnabled && localCandidate != null && localPort > 0) {
            "pmtiles://http://127.0.0.1:$localPort/offline.pmtiles"
        } else {
            val raw = config.activePmtilesUrl
            when {
                raw.endsWith(".json") -> raw
                raw.startsWith("pmtiles://") -> raw
                else -> raw.replace(Regex("\\.pmtiles$", RegexOption.IGNORE_CASE), ".json")
            }
        }

        val isProtomaps = config.darkStyleSchema.equals("protomaps", ignoreCase = true)
        val roadLayer = if (isProtomaps) "roads" else "transportation"
        val bldgLayer = if (isProtomaps) "buildings" else "building"
        val parkLayer = if (isProtomaps) "landuse" else "park"

        // Dual-lighting map palette synced with Karta's karta_dark_style.dart
        val bgHex = if (isDarkMode) "#0D0F12" else "#F5F2EB"
        val waterHex = if (isDarkMode) "#070B12" else "#C9E0EA"
        val parkHex = if (isDarkMode) "#132622" else "#D4E6D9"
        val minorRoadHex = if (isDarkMode) "#252E3B" else "#FFFFFF"
        val majorRoadHex = if (isDarkMode) "#384759" else "#FCEFD8"
        val motorwayCasingHex = if (isDarkMode) "#090B0E" else "#163834"
        val motorwayHex = if (isDarkMode) "#5B9A94" else "#2F756F"
        val bldgFillHex = if (isDarkMode) "#181C22" else "#E2DED4"
        val bldgOutlineHex = if (isDarkMode) "#2B3544" else "#CBC6BA"
        val bldg3DHex = if (isDarkMode) "#222A34" else "#D9D4C8"

        val root = JSONObject()
        root.put("version", 8)
        root.put("name", if (isDarkMode) "Karta Obsidian Night Android Auto v2" else "Karta Tropical Daylight Android Auto v2")

        val sources = JSONObject().put(
            "karta_basemap",
            JSONObject()
                .put("type", "vector")
                .put("url", sourceUrl),
        )
        root.put("sources", sources)

        val layers = JSONArray()
        layers.put(
            JSONObject()
                .put("id", "background")
                .put("type", "background")
                .put("paint", JSONObject().put("background-color", bgHex)),
        )
        layers.put(
            JSONObject()
                .put("id", "parks")
                .put("type", "fill")
                .put("source", "karta_basemap")
                .put("source-layer", parkLayer)
                .put("paint", JSONObject().put("fill-color", parkHex).put("fill-opacity", 0.72)),
        )
        layers.put(
            JSONObject()
                .put("id", "water")
                .put("type", "fill")
                .put("source", "karta_basemap")
                .put("source-layer", "water")
                .put("paint", JSONObject().put("fill-color", waterHex)),
        )
        layers.put(
            JSONObject()
                .put("id", "roads_minor")
                .put("type", "line")
                .put("source", "karta_basemap")
                .put("source-layer", roadLayer)
                .put("minzoom", 11)
                .put(
                    "paint",
                    JSONObject()
                        .put("line-color", minorRoadHex)
                        .put("line-width", 2.4),
                ),
        )
        layers.put(
            JSONObject()
                .put("id", "roads_major")
                .put("type", "line")
                .put("source", "karta_basemap")
                .put("source-layer", roadLayer)
                .put("minzoom", 6)
                .put(
                    "filter",
                    JSONArray(
                        if (isProtomaps) {
                            listOf("in", "kind", "major_road", "medium_road")
                        } else {
                            listOf("in", "class", "primary", "secondary", "tertiary", "trunk")
                        },
                    ),
                )
                .put(
                    "paint",
                    JSONObject()
                        .put("line-color", majorRoadHex)
                        .put("line-width", 4.8),
                ),
        )
        layers.put(
            JSONObject()
                .put("id", "roads_motorway_casing")
                .put("type", "line")
                .put("source", "karta_basemap")
                .put("source-layer", roadLayer)
                .put(
                    "filter",
                    JSONArray(
                        if (isProtomaps) listOf("==", "kind", "highway")
                        else listOf("==", "class", "motorway"),
                    ),
                )
                .put(
                    "paint",
                    JSONObject()
                        .put("line-color", motorwayCasingHex)
                        .put("line-width", 8.6),
                ),
        )
        layers.put(
            JSONObject()
                .put("id", "roads_motorway")
                .put("type", "line")
                .put("source", "karta_basemap")
                .put("source-layer", roadLayer)
                .put(
                    "filter",
                    JSONArray(
                        if (isProtomaps) listOf("==", "kind", "highway")
                        else listOf("==", "class", "motorway"),
                    ),
                )
                .put(
                    "paint",
                    JSONObject()
                        .put("line-color", motorwayHex)
                        .put("line-opacity", if (isDarkMode) 0.9 else 0.95)
                        .put("line-width", 6.2),
                ),
        )
        layers.put(
            JSONObject()
                .put("id", "buildings_footprint")
                .put("type", "fill")
                .put("source", "karta_basemap")
                .put("source-layer", bldgLayer)
                .put("minzoom", 12.5)
                .put(
                    "paint",
                    JSONObject()
                        .put("fill-color", bldgFillHex)
                        .put("fill-outline-color", bldgOutlineHex)
                        .put("fill-opacity", 0.84),
                ),
        )
        layers.put(
            JSONObject()
                .put("id", "buildings_3d")
                .put("type", "fill-extrusion")
                .put("source", "karta_basemap")
                .put("source-layer", bldgLayer)
                .put("minzoom", 13.5)
                .put("layout", JSONObject().put("visibility", if (enable3DBuildings) "visible" else "none"))
                .put(
                    "paint",
                    JSONObject()
                        .put("fill-extrusion-color", bldg3DHex)
                        .put("fill-extrusion-height", 18.0)
                        .put("fill-extrusion-opacity", 0.88),
                ),
        )

        root.put("layers", layers)
        return root.toString()
    }

    private fun acceptLoop(server: ServerSocket) {
        while (running.get() && !server.isClosed) {
            try {
                val client = server.accept()
                executor.execute { serveClient(client) }
            } catch (_: Exception) {
                break
            }
        }
    }

    /** Serves HTTP 200 / 206 Partial Content byte-range requests strictly from localhost. */
    private fun serveClient(socket: Socket) {
        socket.use { client ->
            val file = activeOfflineFile ?: return
            val reader = client.getInputStream().bufferedReader()
            val requestLine = reader.readLine() ?: return
            var rangeHeader: String? = null
            while (true) {
                val line = reader.readLine() ?: break
                if (line.isEmpty()) break
                if (line.startsWith("Range:", ignoreCase = true)) {
                    rangeHeader = line.substringAfter(':').trim()
                }
            }

            val totalLen = file.length()
            var start = 0L
            var end = totalLen - 1L
            var isPartial = false

            if (rangeHeader != null && rangeHeader.startsWith("bytes=")) {
                val parts = rangeHeader.removePrefix("bytes=").split('-')
                start = parts.getOrNull(0)?.toLongOrNull()?.coerceIn(0L, totalLen - 1L) ?: 0L
                end = parts.getOrNull(1)?.toLongOrNull()?.coerceIn(start, totalLen - 1L) ?: (totalLen - 1L)
                isPartial = true
            }

            val contentLen = (end - start) + 1L
            val out = client.getOutputStream()
            val status = if (isPartial) "206 Partial Content" else "200 OK"
            val headers = buildString {
                append("HTTP/1.1 $status\r\n")
                append("Content-Type: application/octet-stream\r\n")
                append("Accept-Ranges: bytes\r\n")
                append("Content-Length: $contentLen\r\n")
                if (isPartial) {
                    append("Content-Range: bytes $start-$end/$totalLen\r\n")
                }
                append("Connection: close\r\n\r\n")
            }
            out.write(headers.toByteArray(Charsets.US_ASCII))

            if (!requestLine.startsWith("HEAD", ignoreCase = true)) {
                RandomAccessFile(file, "r").use { raf ->
                    raf.seek(start)
                    val buffer = ByteArray(16384)
                    var remaining = contentLen
                    while (remaining > 0L) {
                        val toRead = minOf(buffer.size.toLong(), remaining).toInt()
                        val n = raf.read(buffer, 0, toRead)
                        if (n <= 0) break
                        out.write(buffer, 0, n)
                        remaining -= n
                    }
                }
            }
            out.flush()
        }
    }
}
