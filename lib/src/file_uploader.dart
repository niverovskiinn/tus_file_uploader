import 'dart:io';
import 'dart:math';
import 'package:async/async.dart';

import 'package:http/http.dart' as http;
import 'package:cross_file/cross_file.dart' show XFile;

import 'utils.dart';
import 'exceptions.dart';
import 'extensions.dart';

class TusFileUploader {
  static const _defaultChunkSize = 128 * 1024; // 128 KB
  late int _currentChunkSize;
  final _client = http.Client();

  late XFile _file;
  late Uri _uploadUrl;
  late int _optimalChunkSendTime;
  CancelableOperation? _currentOperation;

  final UploadingProgressCallback? progressCallback;
  final UploadingCompleteCallback? completeCallback;
  final UploadingFailedCallback? failureCallback;
  final Map<String, String> headers;
  final bool failOnLostConnection;
  final Uri baseUrl;

  bool uploadingIsPaused = false;

  TusFileUploader({
    required String path,
    required this.baseUrl,
    this.progressCallback,
    this.completeCallback,
    this.failureCallback,
    this.headers = const {},
    this.failOnLostConnection = false,
    int? optimalChunkSendTime,
  }) {
    _file = XFile(path);
    _currentChunkSize = _defaultChunkSize;
    _optimalChunkSendTime = optimalChunkSendTime ?? 1000; // 1 SEC
  }

  Future<String?> setup() async {
    String? uploadUrl;
    try {
      _currentOperation = CancelableOperation.fromFuture(
        _client.setupUploadUrl(
          baseUrl: baseUrl,
          headers: headers,
        ),
      );
      _uploadUrl = await _currentOperation!.value;
      return uploadUrl.toString();
    } catch (e) {
      failureCallback?.call(_file.path, e.toString());
      return null;
    }
  }

  void pause() {
    uploadingIsPaused = true;
    _currentChunkSize = _defaultChunkSize;
    _currentOperation?.cancel();
  }

  Future<void> upload({
    Map<String, String> headers = const {},
  }) async {
    uploadingIsPaused = false;
    try {
      _currentOperation = CancelableOperation.fromFuture(
        _client.getCurrentOffset(
          _uploadUrl,
          headers: headers,
        ),
      );
      final offset = await _currentOperation!.value;
      final totalBytes = await _file.length();
      await _uploadNextChunk(
        offset: offset,
        totalBytes: totalBytes,
      );
    } on MissingUploadOffsetException catch (_) {
      final uploadUrl = await setup();
      if (uploadUrl != null) {
        await upload(headers: headers);
      }
      return;
    } on http.ClientException catch (_) {
      final uploadUrl = await setup();
      if (uploadUrl != null) {
        await upload(headers: headers);
      }
      return;
    } on SocketException catch (e) {
      // Lost internet connection
      if (failOnLostConnection) {
        failureCallback?.call(_file.path, e.toString());
      }
      return;
    } catch (e) {
      failureCallback?.call(_file.path, e.toString());
      return;
    }
  }

  Future<void> _uploadNextChunk({
    required int offset,
    required int totalBytes,
  }) async {
    final byteBuilder = await _file.getData(_currentChunkSize, offset: offset);
    final bytesRead = min(_currentChunkSize, byteBuilder.length);
    final nextChunk = byteBuilder.takeBytes();
    final startTime = DateTime.now();
    _currentOperation = CancelableOperation.fromFuture(
      _client.uploadNextChunkOfFile(
        uploadUrl: _uploadUrl,
        nextChunk: nextChunk,
        headers: {
          "Tus-Resumable": tusVersion,
          "Upload-Offset": "$offset",
          "Content-Type": "application/offset+octet-stream"
        },
      ),
    );
    final serverOffset = await _currentOperation!.value;
    final endTime = DateTime.now();
    final diff = endTime.difference(startTime);
    _currentChunkSize = (_currentChunkSize * (_optimalChunkSendTime / diff.inMilliseconds)).toInt();
    final nextOffset = offset + bytesRead;
    if (nextOffset != serverOffset) {
      throw MissingUploadOffsetException(
        message:
            "response contains different Upload-Offset value ($serverOffset) than expected ($offset)",
      );
    }

    progressCallback?.call(_file.path, nextOffset / totalBytes);
    if (offset == totalBytes) {
      completeCallback?.call(_file.path, _uploadUrl.toString());
    }
    if (uploadingIsPaused) {
      return;
    } else {
      await _uploadNextChunk(
        offset: nextOffset,
        totalBytes: totalBytes,
      );
    }
  }
}
