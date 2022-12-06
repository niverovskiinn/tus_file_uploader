Dart implementation of [tus protocol](https://tus.io/) for Flutter. 
```dart
final uploadingManager = TusFileUploaderManager('https://master.tus.io/files/'); // your server link
uploadingManager.uploadFile(
   localFilePath: <PATH_TO_LOCAL_FILE>,
   completeCallback: <CALLBACK_TO_HANDLE_UPLOADING_COMPLETION>,
   progressCallback: <CALLBACK_TO_HANDLE_UPLOADING_PROCESS>,
   failureCallback: <CALLBACK_TO_HANDLE_UPLOADING_FAILURE>,
);
```


## Features

Allows to pause/resume files uploading.

## Getting started

###### IMPORTANT: to allow your app partial uploading of files your server must also implement tus protocol. 
This package solves the problem of partial files uploading using tus protocol from the client side. The main idea of this protocol is to split files into chunks and upload them one by one controlling the order. In brief, the whole process involves 3 steps: 
 1. Setup connection with server to receive a dedicated link for a file uploading (HTTP POST request).
 2. Get current offset to understand which chunk of the file to upload (HTTP HEAD request).
 3. Upload next chunk of the file (HTTP PATCH request).

## Usage

### Quick start 

The package involves simple uploading manager that provides options of uploading multiple files with contorolling the state of uploading process.
```dart
final uploadingManager = TusFileUploaderManager('https://master.tus.io/files/'); // your server link
uploadingManager.uploadFile(
   localFilePath: <PATH_TO_LOCAL_FILE>,
   completeCallback: <CALLBACK_TO_HANDLE_UPLOADING_COMPLETION>,
   progressCallback: <CALLBACK_TO_HANDLE_UPLOADING_PROCESS>,
   failureCallback: <CALLBACK_TO_HANDLE_UPLOADING_FAILURE>,
);
```
### More flexible approach
The process of uploading files can be managed more precisely by wrapping objects of `TusFileUploader` into your own uploading manager (for example you want to store the information about uploading process in persistent storage to allow resume it after app's crashing). 
- Step 1: init an object of `TusFileUploader` to futher uploading of the file
```dart
final uploader = TusFileUploader(
   path: <PATH_TO_LOCAL_FILE>,
   baseUrl: Uri.parse(<BASE_URL_FOR_FILES_UPLOADING>),
   headers: {
          "Tus-Resumable": <TUS_VERSION>,
          "Upload-Metadata": <UPLOAD_METADATA>,
          "Upload-Length": "<TOTAL_BYTES_IN_THE_FILE>",
        },
   progressCallback: <CALLBACK_TO HANDLE UPLOADING_PROCESS>,
   completeCallback: <CALLBACK_TO HANDLE UPLOADING_COMPLETION>,
   failureCallback: <CALLBACK_TO_HANDLE_UPLOADING_FAILURE>,
);
```
- Step 2: setup the connection with server. The setup process went successfully if the returned upload url is not `null`.
```dart
final uploadUrl = await uploader.setup();
if (uploadUrl != null) {
    // upload your file
}
```
- Setp 3: upload your file with optional headers.
```dart
await uploader.upload(
    headers: {
        // Pass headers if they are needed
    },
);
```