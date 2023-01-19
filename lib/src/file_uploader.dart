import 'dart:io';
import 'dart:math';
import 'package:async/async.dart';

import 'package:cross_file/cross_file.dart' show XFile;

import 'utils.dart';
import 'exceptions.dart';
import 'extensions.dart';

class TusFileUploader {
  static const _defaultChunkSize = 128 * 1024; // 128 KB
  late int _currentChunkSize;
  final _client = HttpClient();

  Uri? _uploadUrl;
  late XFile _file;
  late int _optimalChunkSendTime;
  CancelableOperation? _currentOperation;

  final UploadingProgressCallback? progressCallback;
  final UploadingCompleteCallback? completeCallback;
  final UploadingFailedCallback? failureCallback;
  final Map<String, String> headers;
  final bool failOnLostConnection;
  final Uri baseUrl;

  bool uploadingIsPaused = false;

  TusFileUploader._({
    required String path,
    required this.baseUrl,
    required this.headers,
    required this.failOnLostConnection,
    this.progressCallback,
    this.completeCallback,
    this.failureCallback,
    int? optimalChunkSendTime,
    Uri? uploadUrl,
    int? timeout,
  }) {
    _file = XFile(path);
    _uploadUrl = uploadUrl;
    _currentChunkSize = _defaultChunkSize;
    _optimalChunkSendTime = optimalChunkSendTime ?? 1000; // 1 SEC
    _client.connectionTimeout = Duration(seconds: timeout ?? 3);
  }

  factory TusFileUploader.init({
    required String path,
    required Uri baseUrl,
    UploadingProgressCallback? progressCallback,
    UploadingCompleteCallback? completeCallback,
    UploadingFailedCallback? failureCallback,
    Map<String, String>? headers,
    bool? failOnLostConnection,
    int? optimalChunkSendTime,
    int? timeout,
  }) =>
      TusFileUploader._(
        path: path,
        baseUrl: baseUrl,
        progressCallback: progressCallback,
        completeCallback: completeCallback,
        failureCallback: failureCallback,
        headers: headers ?? const {},
        failOnLostConnection: failOnLostConnection ?? false,
        optimalChunkSendTime: optimalChunkSendTime,
        timeout: timeout,
      );

  factory TusFileUploader.initAndSetup({
    required String path,
    required Uri baseUrl,
    required Uri uploadUrl,
    UploadingProgressCallback? progressCallback,
    UploadingCompleteCallback? completeCallback,
    UploadingFailedCallback? failureCallback,
    Map<String, String>? headers,
    bool? failOnLostConnection,
    int? optimalChunkSendTime,
    int? timeout,
  }) =>
      TusFileUploader._(
        path: path,
        baseUrl: baseUrl,
        progressCallback: progressCallback,
        completeCallback: completeCallback,
        failureCallback: failureCallback,
        headers: headers ?? const {},
        failOnLostConnection: failOnLostConnection ?? false,
        optimalChunkSendTime: optimalChunkSendTime,
        uploadUrl: uploadUrl,
        timeout: timeout,
      );

  Future<String?> setupUploadUrl() async {
    if (_uploadUrl != null) {
      return _uploadUrl!.toString();
    }
    try {
      _currentOperation = CancelableOperation.fromFuture(
        _client.setupUploadUrl(
          baseUrl: baseUrl,
          headers: headers,
        ),
      );
      _uploadUrl = await _currentOperation!.value;
      return _uploadUrl.toString();
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
    _currentOperation = CancelableOperation.fromFuture(() async {
      try {
        final resultUrl = _uploadUrl;
        if (resultUrl == null) {
          throw UnimplementedError('The upload url is missing');
        }
        final offset = await _client.getCurrentOffset(
          resultUrl,
          headers: Map.from(headers)
            ..addAll({
              "Tus-Resumable": tusVersion,
            }),
        );
        final totalBytes = await _file.length();
        await _uploadNextChunk(
          offset: offset,
          totalBytes: totalBytes,
        );
      } on MissingUploadOffsetException catch (_) {
        final uploadUrl = await setupUploadUrl();
        if (uploadUrl != null) {
          await upload(headers: headers);
        }
        return;
      } on HttpException catch (_) {
        // Lost internet connection
        if (failOnLostConnection) {
          failureCallback?.call(_file.path, e.toString());
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
    }.call());
    await _currentOperation!.value;
  }

  Future<void> _uploadNextChunk({
    required int offset,
    required int totalBytes,
  }) async {
    final resultUrl = _uploadUrl;
    if (resultUrl == null) {
      throw UnimplementedError('The upload url is missing');
    }
    final byteBuilder = await _file.getData(_currentChunkSize, offset: offset);
    final bytesRead = min(_currentChunkSize, byteBuilder.length);
    final nextChunk = byteBuilder.takeBytes();
    final startTime = DateTime.now();
    final serverOffset = await _client.uploadNextChunkOfFile(
      uploadUrl: resultUrl,
      nextChunk: nextChunk,
      headers: {
        "Tus-Resumable": tusVersion,
        "Upload-Offset": "$offset",
        "Content-Type": "application/offset+octet-stream"
      },
    );
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
      return;
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
