import 'package:flutter/material.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/desktop/pages/remote_page.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:get/get.dart';

/// A live "wall" of every open remote session, laid out in a grid.
///
/// Each session already stays connected and keeps decoding while its tab is in
/// the background (`_RemotePageState` uses `AutomaticKeepAliveClientMixin` with
/// `wantKeepAlive => true`), so this view does not open anything new — it just
/// renders each session's existing video texture as a tile. Tapping a tile jumps
/// to that session's tab for full control.
class RemoteWallView extends StatelessWidget {
  final DesktopTabController tabController;

  /// Called after a tile is tapped, so the parent can leave wall mode.
  final VoidCallback onTileTap;

  const RemoteWallView({
    Key? key,
    required this.tabController,
    required this.onTileTap,
  }) : super(key: key);

  /// Grid columns sized so tiles stay roughly square-ish as sessions are added.
  static int columnsFor(int count) {
    if (count <= 1) return 1;
    if (count <= 4) return 2;
    if (count <= 9) return 3;
    if (count <= 16) return 4;
    return 5;
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final tabs = tabController.state.value.tabs;
      if (tabs.isEmpty) {
        return Container(
          color: Colors.black,
          alignment: Alignment.center,
          child: const Text(
            'No open sessions',
            style: TextStyle(color: Colors.white54),
          ),
        );
      }
      return Container(
        color: Colors.black,
        padding: const EdgeInsets.all(8),
        child: GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columnsFor(tabs.length),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 16 / 10,
          ),
          itemCount: tabs.length,
          itemBuilder: (context, index) => _WallTile(
            tab: tabs[index],
            onTap: () {
              tabController.jumpTo(index);
              onTileTap();
            },
          ),
        ),
      );
    });
  }
}

class _WallTile extends StatelessWidget {
  final TabInfo tab;
  final VoidCallback onTap;

  const _WallTile({Key? key, required this.tab, required this.onTap})
      : super(key: key);

  /// The session behind this tab, or null if its page has not built yet.
  FFI? get _ffi {
    try {
      final page = tab.page;
      if (page is RemotePage) return page.ffi;
    } catch (_) {
      // RemotePage.ffi throws until the page's state has been created.
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ffi = _ffi;
    return Material(
      color: Colors.black,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white24),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ffi == null ? _connecting() : _video(ffi),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  color: Colors.black.withOpacity(0.6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  child: Text(
                    tab.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _connecting() => const Center(
        child: Text('Connecting...', style: TextStyle(color: Colors.white54)),
      );

  Widget _video(FFI ffi) {
    final cur = ffi.ffiModel.pi.currentDisplay;
    final display = cur == kAllDisplayValue ? 0 : cur;
    final textureId = ffi.textureModel.getTextureId(display);
    return Obx(() {
      if (textureId.value == -1) {
        return _connecting();
      }
      final rect = ffi.ffiModel.rect;
      final aspect = (rect != null && rect.height > 0)
          ? rect.width / rect.height
          : 16 / 9;
      return Center(
        child: AspectRatio(
          aspectRatio: aspect,
          child: Texture(
            textureId: textureId.value,
            filterQuality: FilterQuality.low,
          ),
        ),
      );
    });
  }
}
