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
    private var initialIntentUri: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIncomingIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIncomingIntent(intent)
    }

    private fun handleIncomingIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action
        if (Intent.ACTION_VIEW == action) {
            intent.data?.let { uri ->
                initialIntentUri = uri.toString()
            }
        } else if (Intent.ACTION_SEND == action) {
            val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            uri?.let {
                initialIntentUri = it.toString()
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "openDocument" -> {
                    if (pendingResult != null) {
                        result.error("BUSY", "A file picker session is already active", null)
                        return@setMethodCallHandler
                    }
                    pendingResult = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "*/*"
                    }
                    try {
                        startActivityForResult(intent, REQUEST_CODE_OPEN_DOCUMENT)
                    } catch (e: Exception) {
                        pendingResult = null
                        result.error("UNAVAILABLE", "Storage Access Framework is not available: ${e.message}", null)
                    }
                }
                "getInitialIntentUri" -> {
                    val uri = initialIntentUri
                    initialIntentUri = null
                    result.success(uri)
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
}
