
const tusVersion = "1.0.0";

typedef UploadingProgressCallback = void Function(String filePath, double progress);
typedef UploadingCompleteCallback = void Function(String filePath, String uploadUrl);
typedef UploadingFailedCallback = void Function(String filePath, String message);