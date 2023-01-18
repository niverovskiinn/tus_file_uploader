import 'dart:convert';
import 'dart:io';
import 'package:collection/collection.dart';
import 'dart:typed_data' show Uint8List;

import 'package:cross_file/cross_file.dart' show XFile;
import "package:path/path.dart" as p;

import 'utils.dart';
import 'exceptions.dart';

extension HttpClientUtils on HttpClient {
  Future<Uri> setupUploadUrl({
    required Uri baseUrl,
    Map<String, String> headers = const {},
  }) async {
    final request = await postUrl(baseUrl);
    headers.forEach((key, value) {
      request.headers.set(key, value);
    });
    final response = await request.close();
    if (!(response.statusCode >= 200 && response.statusCode < 300) && response.statusCode != 404) {
      throw ProtocolException(response.statusCode);
    }
    final list = response.headers["location"];
    final urlStr = list?.firstOrNull ?? "";
    if (urlStr.isEmpty) {
      throw MissingUploadUriException();
    }
    return baseUrl.parseUrl(urlStr);
  }

  Future<int> getCurrentOffset(
    Uri uploadUrl, {
    Map<String, String>? headers,
  }) async {
    final request = await headUrl(uploadUrl);
    request.headers.set(tusVersion, "Tus-Resumable");
    headers?.forEach((key, value) {
      request.headers.set(key, value);
    });
    final response = await request.close();
    if (!(response.statusCode >= 200 && response.statusCode < 300)) {
      throw ProtocolException(response.statusCode);
    }
    final list = response.headers["upload-offset"];
    final serverOffset = list?.firstOrNull?.parseOffset();
    if (serverOffset == null) {
      throw MissingUploadOffsetException();
    }
    return serverOffset;
  }

  Future<int> uploadNextChunkOfFile({
    required Uri uploadUrl,
    required Uint8List nextChunk,
    Map<String, String> headers = const {},
  }) async {
    final request = await patchUrl(uploadUrl);
    headers.forEach((key, value) {
      request.headers.set(key, value);
    });
    request.add(nextChunk);
    final response = await request.close();

    if (!(response.statusCode >= 200 && response.statusCode < 300)) {
      throw ProtocolException(response.statusCode);
    }

    final list = response.headers["upload-offset"];
    final serverOffset = list?.firstOrNull?.parseOffset();
    if (serverOffset == null) {
      throw ChunkUploadFailedException();
    }
    return serverOffset;
  }
}

extension XFileUtils on XFile {
  Future<BytesBuilder> getData(int maxChunkSize, {int? offset}) async {
    final start = offset ?? 0;
    int end = start + maxChunkSize;
    final fileSize = await length();
    end = end > fileSize ? fileSize : end;

    final result = BytesBuilder();
    await for (final chunk in openRead(start, end)) {
      result.add(chunk);
    }
    return result;
  }

  String generateMetadata({Map<String, String>? originalMetadata}) {
    final meta = Map<String, String>.from(originalMetadata ?? {});

    if (!meta.containsKey("filename")) {
      meta["filename"] = p.basename(path);
    }

    return meta.entries
        .map((entry) => "${entry.key} ${base64.encode(utf8.encode(entry.value))}")
        .join(",");
  }

  String? generateFingerprint() {
    return path.replaceAll(RegExp(r"\W+"), '.');
  }
}

extension UriTus on Uri {
  Uri parseUrl(String urlStr) {
    String resultUrlStr = urlStr;
    if (urlStr.contains(",")) {
      resultUrlStr = urlStr.substring(0, urlStr.indexOf(","));
    }
    Uri uploadUrl = Uri.parse(resultUrlStr);
    if (uploadUrl.host.isEmpty) {
      uploadUrl = uploadUrl.replace(host: host, port: port);
    }
    if (uploadUrl.scheme.isEmpty) {
      uploadUrl = uploadUrl.replace(scheme: scheme);
    }
    return uploadUrl;
  }
}

extension StringTus on String {
  int? parseOffset() {
    if (isEmpty) {
      return null;
    }
    String offset = this;
    if (offset.contains(",")) {
      offset = offset.substring(0, offset.indexOf(","));
    }
    return int.tryParse(offset);
  }
}
