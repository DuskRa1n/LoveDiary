part of '../../app.dart';

class AttachmentGrid extends StatelessWidget {
  const AttachmentGrid({
    super.key,
    required this.attachments,
    required this.rootDirectoryPath,
    this.shrinkWrap = true,
    this.physics = const NeverScrollableScrollPhysics(),
  });

  final List<DiaryAttachment> attachments;
  final String? rootDirectoryPath;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: shrinkWrap,
      physics: physics,
      itemCount: attachments.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemBuilder: (context, index) {
        final attachment = attachments[index];
        return InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AttachmentPreviewPage(
                  attachments: attachments,
                  rootDirectoryPath: rootDirectoryPath,
                  initialIndex: index,
                ),
              ),
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox.expand(
              child: DiaryAttachmentImage(
                attachment: attachment,
                rootDirectoryPath: rootDirectoryPath,
                fit: BoxFit.cover,
              ),
            ),
          ),
        );
      },
    );
  }
}

class EditableAttachmentGrid extends StatelessWidget {
  const EditableAttachmentGrid({
    super.key,
    required this.attachments,
    required this.rootDirectoryPath,
    required this.onRemove,
  });

  final List<DiaryAttachment> attachments;
  final String? rootDirectoryPath;
  final ValueChanged<DiaryAttachment> onRemove;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: attachments.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemBuilder: (context, index) {
        final attachment = attachments[index];
        return Stack(
          fit: StackFit.expand,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AttachmentPreviewPage(
                      attachments: attachments,
                      rootDirectoryPath: rootDirectoryPath,
                      initialIndex: index,
                    ),
                  ),
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: SizedBox.expand(
                  child: DiaryAttachmentImage(
                    attachment: attachment,
                    rootDirectoryPath: rootDirectoryPath,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: InkWell(
                onTap: () => onRemove(attachment),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(4),
                  child: const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class DiaryAttachmentImage extends StatelessWidget {
  const DiaryAttachmentImage({
    super.key,
    required this.attachment,
    required this.rootDirectoryPath,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.preferOriginal = false,
  });

  final DiaryAttachment attachment;
  final String? rootDirectoryPath;
  final BoxFit fit;
  final double? width;
  final double? height;
  final bool preferOriginal;

  @override
  Widget build(BuildContext context) {
    final path = preferOriginal
        ? attachment.originalOrFallbackPath
        : attachment.previewOrFallbackPath;
    if (path.isEmpty || kIsWeb) {
      return _AttachmentPlaceholder(width: width, height: height);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
        final constrainedWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : null;
        final constrainedHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : null;
        final targetWidth = width ?? constrainedWidth;
        final targetHeight = height ?? constrainedHeight;

        return Image.file(
          File(resolveStoredPath(rootDirectoryPath, path)),
          width: targetWidth,
          height: targetHeight,
          fit: fit,
          cacheWidth: preferOriginal
              ? null
              : _attachmentCacheExtent(targetWidth, devicePixelRatio),
          filterQuality: preferOriginal
              ? FilterQuality.high
              : FilterQuality.medium,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) =>
              _AttachmentPlaceholder(width: targetWidth, height: targetHeight),
        );
      },
    );
  }
}

int? _attachmentCacheExtent(double? logicalExtent, double devicePixelRatio) {
  if (logicalExtent == null || !logicalExtent.isFinite || logicalExtent <= 0) {
    return null;
  }
  return (logicalExtent * devicePixelRatio).ceil();
}

class AttachmentPreviewPage extends StatefulWidget {
  const AttachmentPreviewPage({
    super.key,
    required this.attachments,
    required this.rootDirectoryPath,
    required this.initialIndex,
  });

  final List<DiaryAttachment> attachments;
  final String? rootDirectoryPath;
  final int initialIndex;

  @override
  State<AttachmentPreviewPage> createState() => _AttachmentPreviewPageState();
}

class _AttachmentPreviewPageState extends State<AttachmentPreviewPage> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final attachment = widget.attachments[_currentIndex];
    final fileName = attachment.originalName.isEmpty
        ? '图片 ${_currentIndex + 1}'
        : attachment.originalName;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_currentIndex + 1}/${widget.attachments.length}'),
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.attachments.length,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            itemBuilder: (context, index) {
              return Center(
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: DiaryAttachmentImage(
                      attachment: widget.attachments[index],
                      rootDirectoryPath: widget.rootDirectoryPath,
                      fit: BoxFit.contain,
                      preferOriginal: true,
                    ),
                  ),
                ),
              );
            },
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.photo_library_outlined,
                      color: Colors.white70,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentPlaceholder extends StatelessWidget {
  const _AttachmentPlaceholder({this.width, this.height});

  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: const Color(0xFFFFEFF5),
      alignment: Alignment.center,
      child: const Icon(Icons.image_outlined, color: Color(0xFFC85C8E)),
    );
  }
}
