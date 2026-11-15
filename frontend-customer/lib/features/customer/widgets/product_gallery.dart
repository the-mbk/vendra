// ══════════════════════════════════════════════════════════════
// Vendra Customer App - Product photo gallery (FR06)
// ProductGallery     swipeable photos (cover first) with page dots; tap
//                    opens the full-screen viewer
// PhotoViewerScreen  black full-screen viewer: pinch / double-tap to
//                    zoom (InteractiveViewer), swipe between photos
// Photo URLs are server paths, resolved with ApiConfig.fileUrl. A missing
// or broken photo falls back to the ProductImage placeholder.
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:vendra_customer/vendra_core.dart';

/// One gallery photo, or the product placeholder if it can't be loaded
class GalleryPhotoImage extends StatelessWidget {
  final String url;
  final ProductModel product;
  final BoxFit fit;
  final double iconSize;

  const GalleryPhotoImage({
    super.key,
    required this.url,
    required this.product,
    this.fit = BoxFit.cover,
    this.iconSize = 80,
  });

  @override
  Widget build(BuildContext context) {
    Widget placeholder() => ProductImage(product: product, iconSize: iconSize);
    return Image.network(
      ApiConfig.fileUrl(url),
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => placeholder(),
      loadingBuilder: (context, img, progress) => progress == null ? img : placeholder(),
    );
  }
}

/// Page dots under a gallery
class PageDots extends StatelessWidget {
  final int count;
  final int index;
  final Color activeColor;
  final Color inactiveColor;

  const PageDots({
    super.key,
    required this.count,
    required this.index,
    this.activeColor = Colors.white,
    this.inactiveColor = Colors.white54,
  });

  @override
  Widget build(BuildContext context) {
    // Many photos: keep the dots within narrow screens
    final dot = count > 12 ? 5.0 : 7.0;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 5,
      runSpacing: 4,
      children: List.generate(count, (i) {
        final active = i == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: active ? dot * 2.4 : dot,
          height: dot,
          decoration: BoxDecoration(
            color: active ? activeColor : inactiveColor,
            borderRadius: BorderRadius.circular(dot),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2)],
          ),
        );
      }),
    );
  }
}

class ProductGallery extends StatefulWidget {
  final ProductModel product;
  final List<String> images;
  final double height;

  /// Drawn over the photos (badges)
  final List<Widget> overlays;

  const ProductGallery({
    super.key,
    required this.product,
    required this.images,
    this.height = 300,
    this.overlays = const [],
  });

  @override
  State<ProductGallery> createState() => _ProductGalleryState();
}

class _ProductGalleryState extends State<ProductGallery> {
  final _pages = PageController();
  int _index = 0;

  @override
  void didUpdateWidget(covariant ProductGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The full gallery replaced the list's single cover photo
    if (_index >= widget.images.length && widget.images.isNotEmpty) {
      _index = 0;
      if (_pages.hasClients) _pages.jumpToPage(0);
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _openViewer() async {
    final last = await Navigator.of(context).push<int>(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (_, __, ___) =>
          PhotoViewerScreen(images: widget.images, product: widget.product, initialIndex: _index),
      transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
    ));
    if (last != null && last != _index && mounted && _pages.hasClients) _pages.jumpToPage(last);
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.images;
    return SizedBox(
      width: double.infinity,
      height: widget.height,
      child: Stack(
        children: [
          Positioned.fill(
            child: images.isEmpty
                ? ProductImage(product: widget.product, iconSize: 80)
                : PageView.builder(
                    controller: _pages,
                    itemCount: images.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) => GestureDetector(
                      onTap: _openViewer,
                      child: Semantics(
                        button: true,
                        label: 'Photo ${i + 1} of ${images.length}. Tap to zoom',
                        child: GalleryPhotoImage(url: images[i], product: widget.product),
                      ),
                    ),
                  ),
          ),
          ...widget.overlays,
          if (images.isNotEmpty)
            Positioned(
              right: 12,
              bottom: 12,
              child: Material(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  onTap: _openViewer,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.zoom_in, size: 16, color: Colors.white),
                        if (images.length > 1) ...[
                          const SizedBox(width: 4),
                          Text('${_index + 1}/${images.length}',
                              style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600)),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (images.length > 1)
            Positioned(
              left: 70,
              right: 70,
              bottom: 16,
              child: PageDots(count: images.length, index: _index),
            ),
        ],
      ),
    );
  }
}

/// Full-screen photos with pinch-zoom. Pops with the index last shown.
class PhotoViewerScreen extends StatefulWidget {
  final List<String> images;
  final ProductModel product;
  final int initialIndex;

  const PhotoViewerScreen({super.key, required this.images, required this.product, this.initialIndex = 0});

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  late final PageController _pages = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  /// While a photo is zoomed in, dragging pans it instead of changing photo
  bool _zoomed = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).pop(_index);

  @override
  Widget build(BuildContext context) {
    final count = widget.images.length;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(
              child: PageView.builder(
                controller: _pages,
                itemCount: count,
                physics: _zoomed ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
                onPageChanged: (i) => setState(() {
                  _index = i;
                  _zoomed = false;
                }),
                itemBuilder: (context, i) => _ZoomablePhoto(
                  url: widget.images[i],
                  product: widget.product,
                  onZoomChanged: (z) {
                    if (z != _zoomed && i == _index) setState(() => _zoomed = z);
                  },
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Close',
                      onPressed: _close,
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                    Expanded(
                      child: Text(
                        widget.product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
                      ),
                    ),
                    if (count > 1)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Text('${_index + 1} / $count',
                            style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      ),
                  ],
                ),
              ),
            ),
            if (count > 1)
              Positioned(
                left: 40,
                right: 40,
                bottom: 24,
                child: SafeArea(top: false, child: PageDots(count: count, index: _index)),
              ),
          ],
        ),
      ),
    );
  }
}

class _ZoomablePhoto extends StatefulWidget {
  final String url;
  final ProductModel product;
  final ValueChanged<bool> onZoomChanged;

  const _ZoomablePhoto({required this.url, required this.product, required this.onZoomChanged});

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto> {
  static const _doubleTapScale = 2.5;

  final _transform = TransformationController();
  Offset _tapAt = Offset.zero;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransform);
  }

  void _onTransform() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) {
      _zoomed = zoomed;
      widget.onZoomChanged(zoomed);
    }
  }

  void _toggleZoom() {
    if (_zoomed) {
      _transform.value = Matrix4.identity();
    } else {
      // Zoom in around the tapped point
      final p = _tapAt;
      _transform.value = Matrix4.identity()
        ..translateByDouble(-p.dx * (_doubleTapScale - 1), -p.dy * (_doubleTapScale - 1), 0, 1)
        ..scaleByDouble(_doubleTapScale, _doubleTapScale, 1, 1);
    }
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransform);
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: (d) => _tapAt = d.localPosition,
      onDoubleTap: _toggleZoom,
      child: InteractiveViewer(
        transformationController: _transform,
        minScale: 1,
        maxScale: 5,
        child: Center(
          child: GalleryPhotoImage(url: widget.url, product: widget.product, fit: BoxFit.contain, iconSize: 96),
        ),
      ),
    );
  }
}
