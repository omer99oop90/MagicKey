package com.magickey.app

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.magickey/saf"
    private val PDF_CHANNEL = "com.magickey/pdf"
    private val REQUEST_CODE_OPEN_DOCUMENT = 4201

    private var pendingResult: MethodChannel.Result? = null
    private var pendingIntentUri: String? = null
    private var isFlutterReady: Boolean = false
    private var methodChannel: MethodChannel? = null

    // PDF Session Management
    private class PdfSession(
        val id: String,
        val renderer: PdfRenderer,
        val pfd: ParcelFileDescriptor,
        val tempFile: File? = null
    ) {
        fun close() {
            try {
                renderer.close()
            } catch (_: Exception) {}
            try {
                pfd.close()
            } catch (_: Exception) {}
            tempFile?.let {
                try {
                    if (it.exists()) it.delete()
                } catch (_: Exception) {}
            }
        }
    }

    private val activePdfSessions = ConcurrentHashMap<String, PdfSession>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIncomingIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncomingIntent(intent)
    }

    private fun extractUriFromIntent(intent: Intent?): String? {
        if (intent == null) return null
        val action = intent.action ?: return null
        return when (action) {
            Intent.ACTION_VIEW -> {
                intent.data?.toString()
            }
            Intent.ACTION_SEND -> {
                @Suppress("DEPRECATION")
                val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                uri?.toString()
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                @Suppress("DEPRECATION")
                val uris = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                uris?.firstOrNull()?.toString()
            }
            else -> null
        }
    }

    private fun handleIncomingIntent(intent: Intent?) {
        val uriStr = extractUriFromIntent(intent) ?: return

        try {
            val uri = Uri.parse(uriStr)
            val takeFlags: Int = Intent.FLAG_GRANT_READ_URI_PERMISSION
            contentResolver.takePersistableUriPermission(uri, takeFlags)
        } catch (_: SecurityException) {
            // Not all document providers support persistable permissions
        } catch (_: Exception) {}

        deliverOrQueueIntentUri(uriStr)
    }

    private fun deliverOrQueueIntentUri(uriStr: String) {
        val channel = methodChannel
        if (isFlutterReady && channel != null) {
            channel.invokeMethod("onNewIntentUri", uriStr)
        } else {
            pendingIntentUri = uriStr
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel = channel

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "openDocument" -> {
                    if (pendingResult != null) {
                        result.error("BUSY", "A file picker session is already active", null)
                        return@setMethodCallHandler
                    }
                    pendingResult = result
                    val mimeType = call.argument<String>("mimeType") ?: "*/*"
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        if (mimeType.contains(",")) {
                            type = "*/*"
                            val types = mimeType.split(",").map { it.trim() }.toTypedArray()
                            putExtra(Intent.EXTRA_MIME_TYPES, types)
                        } else {
                            type = mimeType
                        }
                    }
                    try {
                        startActivityForResult(intent, REQUEST_CODE_OPEN_DOCUMENT)
                    } catch (e: Exception) {
                        pendingResult = null
                        result.error("UNAVAILABLE", "Storage Access Framework is not available: ${e.message}", null)
                    }
                }
                "getInitialIntentUri" -> {
                    isFlutterReady = true
                    val uri = pendingIntentUri
                    pendingIntentUri = null
                    result.success(uri)
                }
                "notifyReadyForIntents" -> {
                    isFlutterReady = true
                    val uri = pendingIntentUri
                    if (uri != null) {
                        pendingIntentUri = null
                        channel.invokeMethod("onNewIntentUri", uri)
                    }
                    result.success(true)
                }
                "getMetadata" -> {
                    val uriStr = call.argument<String>("uri")
                    if (uriStr == null) {
                        result.error("INVALID_ARGS", "Missing URI argument", null)
                        return@setMethodCallHandler
                    }
                    val metadata = resolveMetadata(Uri.parse(uriStr))
                    result.success(metadata)
                }
                "readUriHeader" -> {
                    val uriStr = call.argument<String>("uri")
                    val maxBytes = call.argument<Int>("maxBytes") ?: 512
                    if (uriStr == null) {
                        result.error("INVALID_ARGS", "Missing URI argument", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val uri = Uri.parse(uriStr)
                        contentResolver.openInputStream(uri)?.use { stream ->
                            val buffer = ByteArray(maxBytes)
                            val bytesRead = stream.read(buffer)
                            if (bytesRead > 0) {
                                result.success(buffer.copyOf(bytesRead))
                            } else {
                                result.success(ByteArray(0))
                            }
                        } ?: result.error("OPEN_FAILED", "Failed to open input stream for URI", null)
                    } catch (e: Exception) {
                        result.error("IO_ERROR", "Error reading URI header: ${e.message}", null)
                    }
                }
                "readUriChunk" -> {
                    val uriStr = call.argument<String>("uri")
                    val offset = (call.argument<Number>("offset") ?: 0).toLong()
                    val length = call.argument<Int>("length") ?: 4096
                    if (uriStr == null) {
                        result.error("INVALID_ARGS", "Missing URI argument", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val uri = Uri.parse(uriStr)
                        contentResolver.openFileDescriptor(uri, "r")?.use { pfd ->
                            FileInputStream(pfd.fileDescriptor).use { fis ->
                                fis.channel.position(offset)
                                val buffer = ByteArray(length)
                                val bytesRead = fis.read(buffer)
                                if (bytesRead > 0) {
                                    result.success(buffer.copyOf(bytesRead))
                                } else {
                                    result.success(ByteArray(0))
                                }
                            }
                        } ?: result.error("OPEN_FAILED", "Failed to open file descriptor for URI", null)
                    } catch (e: Exception) {
                        result.error("IO_ERROR", "Error reading URI chunk: ${e.message}", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Setup Dedicated PDF Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PDF_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "openPdf" -> {
                    val uriStr = call.argument<String>("uri")
                    val path = call.argument<String>("path")

                    var tempFile: File? = null
                    var pfd: ParcelFileDescriptor? = null

                    try {
                        if (uriStr != null) {
                            val uri = Uri.parse(uriStr)
                            pfd = try {
                                contentResolver.openFileDescriptor(uri, "r")
                            } catch (_: Exception) {
                                null
                            }

                            // If direct PFD is null or fails, fall back to streaming into private cache file
                            if (pfd == null) {
                                val inputStream = contentResolver.openInputStream(uri)
                                    ?: throw IOException("Unable to open input stream for URI: $uriStr")
                                val cached = File.createTempFile("magickey_pdf_", ".pdf", cacheDir)
                                tempFile = cached
                                inputStream.use { input ->
                                    FileOutputStream(cached).use { output ->
                                        input.copyTo(output)
                                    }
                                }
                                pfd = ParcelFileDescriptor.open(cached, ParcelFileDescriptor.MODE_READ_ONLY)
                            }
                        } else if (path != null) {
                            val file = File(path)
                            if (!file.exists()) {
                                throw IOException("File does not exist: $path")
                            }
                            pfd = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
                        } else {
                            throw IllegalArgumentException("Neither URI nor path was provided")
                        }

                        val nonNullPfd = pfd ?: throw IOException("Failed to obtain ParcelFileDescriptor")

                        val renderer = try {
                            PdfRenderer(nonNullPfd)
                        } catch (e: SecurityException) {
                            nonNullPfd.close()
                            tempFile?.delete()
                            result.error("ENCRYPTED_PDF", "This PDF document is encrypted or password-protected.", null)
                            return@setMethodCallHandler
                        } catch (e: Exception) {
                            nonNullPfd.close()
                            tempFile?.delete()
                            result.error("MALFORMED_PDF", "The PDF structure is invalid or corrupted: ${e.message}", null)
                            return@setMethodCallHandler
                        }

                        val pageCount = renderer.pageCount
                        val pagesList = mutableListOf<Map<String, Any>>()
                        for (i in 0 until pageCount) {
                            val page = renderer.openPage(i)
                            pagesList.add(mapOf(
                                "pageIndex" to i,
                                "width" to page.width,
                                "height" to page.height
                            ))
                            page.close()
                        }

                        val sessionId = UUID.randomUUID().toString()
                        activePdfSessions[sessionId] = PdfSession(sessionId, renderer, nonNullPfd, tempFile)

                        result.success(mapOf(
                            "sessionId" to sessionId,
                            "pageCount" to pageCount,
                            "pages" to pagesList
                        ))
                    } catch (e: Exception) {
                        try { pfd?.close() } catch (_: Exception) {}
                        try { tempFile?.delete() } catch (_: Exception) {}
                        result.error("OPEN_FAILED", "Failed to open PDF document: ${e.message}", null)
                    }
                }
                "renderPage" -> {
                    val sessionId = call.argument<String>("sessionId")
                    val pageIndex = call.argument<Int>("pageIndex") ?: 0
                    val targetWidth = call.argument<Int>("targetWidth") ?: 1080

                    val session = activePdfSessions[sessionId]
                    if (session == null) {
                        result.error("SESSION_NOT_FOUND", "PDF session $sessionId does not exist or was closed", null)
                        return@setMethodCallHandler
                    }

                    if (pageIndex < 0 || pageIndex >= session.renderer.pageCount) {
                        result.error("INVALID_PAGE", "Page index $pageIndex is out of range", null)
                        return@setMethodCallHandler
                    }

                    try {
                        synchronized(session.renderer) {
                            val page = session.renderer.openPage(pageIndex)
                            val aspectRatio = page.height.toFloat() / page.width.toFloat()
                            val targetHeight = (targetWidth * aspectRatio).toInt().coerceAtLeast(1)

                            val bitmap = Bitmap.createBitmap(targetWidth, targetHeight, Bitmap.Config.ARGB_8888)
                            bitmap.eraseColor(Color.WHITE)

                            page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                            page.close()

                            val stream = ByteArrayOutputStream()
                            bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
                            bitmap.recycle()

                            result.success(stream.toByteArray())
                        }
                    } catch (e: Exception) {
                        result.error("RENDER_ERROR", "Failed to render page $pageIndex: ${e.message}", null)
                    }
                }
                "closePdf" -> {
                    val sessionId = call.argument<String>("sessionId")
                    if (sessionId != null) {
                        val session = activePdfSessions.remove(sessionId)
                        session?.close()
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE_OPEN_DOCUMENT) {
            val res = pendingResult
            pendingResult = null
            if (resultCode == Activity.RESULT_OK && data?.data != null) {
                val uri = data.data!!
                try {
                    val takeFlags: Int = Intent.FLAG_GRANT_READ_URI_PERMISSION
                    contentResolver.takePersistableUriPermission(uri, takeFlags)
                } catch (_: SecurityException) {
                    // Not all document providers support persistable permissions
                }
                val metadata = resolveMetadata(uri)
                res?.success(metadata)
            } else {
                // User cancelled or selection failed
                res?.success(null)
            }
        }
    }

    private fun resolveMetadata(uri: Uri): Map<String, Any> {
        var name = uri.lastPathSegment ?: "unknown_file"
        var size: Long = -1

        try {
            contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (nameIndex != -1) {
                        name = cursor.getString(nameIndex) ?: name
                    }
                    val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (sizeIndex != -1 && !cursor.isNull(sizeIndex)) {
                        size = cursor.getLong(sizeIndex)
                    }
                }
            }
        } catch (_: Exception) {}

        return mapOf(
            "uri" to uri.toString(),
            "name" to name,
            "size" to size
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        super.cleanUpFlutterEngine(flutterEngine)
        methodChannel = null
        isFlutterReady = false
        for ((_, session) in activePdfSessions) {
            session.close()
        }
        activePdfSessions.clear()
    }
}
