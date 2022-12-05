import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

class ImageTile extends StatefulWidget {
  final String path;
  final double? progress;

  const ImageTile(
    this.path, {
    Key? key,
    this.progress,
  }) : super(key: key);

  @override
  State<ImageTile> createState() => _ImageTileState();
}

class _ImageTileState extends State<ImageTile> {
  @override
  Widget build(BuildContext context) {
    final progress = widget.progress ?? 0;
    late FileState fileState;
    if (progress == 0) {
      fileState = FileState.local;
    } else if (progress == 1) {
      fileState = FileState.loaded;
    } else {
      fileState = FileState.loading;
    }
    return Container(
      height: 240,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        image: DecorationImage(
          image: FileImage(File(widget.path)),
          fit: BoxFit.fitWidth,
        ),
      ),
      child: Stack(
        children: [
          if (fileState != FileState.loaded)
            const Positioned(
              top: 0,
              right: 0,
              left: 0,
              bottom: 0,
              child: BlurredWidget(),
            ),
          if (fileState == FileState.loading)
            Align(
              child: CircularProgressIndicator(
                value: widget.progress,
                semanticsLabel: 'Circular progress indicator',
              ),
            ),
        ],
      ),
    );
  }
}

class BlurredWidget extends StatelessWidget {
  const BlurredWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6.0, sigmaY: 6.0),
        child: Container(
          color: Colors.white.withOpacity(0.0),
        ),
      ),
    );
  }
}

enum FileState {
  local,
  loading,
  loaded,
}

enum UploadingState {
  notStarted,
  uploading,
  paused,
}
