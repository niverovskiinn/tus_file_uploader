
class ProtocolException implements Exception {
  final int statusCode;

  ProtocolException(this.statusCode);

  @override
  String toString() =>
      'ProtocolException: unexpected status code ($statusCode) while uploading chunk';
}

class MissingUploadOffsetException implements Exception {
  final String? message;

  MissingUploadOffsetException({
    this.message,
  });

  @override
  String toString() =>
      "MissingUploadOffsetException: ${message ?? 'response for resuming upload is empty'}";
}

class ChunkUploadFailedException implements Exception {
  @override
  String toString() =>
      'ChunkUploadFailedException: response to PATCH request contains no or invalid Upload-Offset header';
}

class MissingUploadUriException implements Exception {
  @override
  String toString() =>
      'MissingUploadUriException: missing upload Uri in response for creating upload';
}