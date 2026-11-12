package com.magickey.app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.FileInputStream
import java.io.InputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.magickey/saf"
    private val REQUEST_CODE_OPEN_DOCUMENT = 4201

    private var pendingResult: MethodChannel.Result? = null
    private var pendingIntentUri: String? = null
    private var isFlutterReady: Boolean = false
    private var methodChannel: MethodChannel? = null

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
    }
}
