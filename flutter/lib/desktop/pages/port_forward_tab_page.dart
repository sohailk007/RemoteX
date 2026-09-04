import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/desktop/pages/port_forward_page.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';

class PortForwardTabPage extends StatefulWidget {
  final Map<String, dynamic> params;

  const PortForwardTabPage({Key? key, required this.params}) : super(key: key);

  @override
  State<PortForwardTabPage> createState() => _PortForwardTabPageState(params);
}

class _PortForwardTabPageState extends State<PortForwardTabPage>
    with WindowListener {
  late final DesktopTabController tabController;
  late final bool isRDP;

  // When true, this window is a RECONNECT of an already-configured tunnel: keep it hidden.
  bool _keepHidden = false;
  DateTime _hideGuardUntil = DateTime.fromMillisecondsSinceEpoch(0);

  static const IconData selectedIcon = Icons.forward_sharp;
  static const IconData unselectedIcon = Icons.forward_outlined;

  // Does this peer already have a saved TCP tunnel? If so the window opened for a silent
  // reconnect (not for setup), so we hide it. A peer with no forwards yet = fresh setup.
  bool _peerHasForwards(String? id) {
    if (id == null || id.isEmpty) return false;
    try {
      final cfg = jsonDecode(bind.mainGetPeerSync(id: id));
      final pf = cfg['port_forwards'];
      return pf is List && pf.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _hideNow() async {
    try {
      await windowManager.setSkipTaskbar(true);
      await windowManager.hide();
    } catch (_) {}
  }

  // Hide the window and keep it hidden for a few seconds -- re-hiding beats the native
  // window's show() and the "Connected" state change that would otherwise pop it back up.
  void _hideReconnectWindow() {
    _keepHidden = true;
    _hideGuardUntil = DateTime.now().add(const Duration(seconds: 8));
    _hideNow();
    for (final ms in [120, 350, 800, 1500, 2600, 4200, 6500]) {
      Future.delayed(Duration(milliseconds: ms), () {
        if (mounted && _keepHidden) _hideNow();
      });
    }
  }

  @override
  void onWindowFocus() {
    if (_keepHidden && DateTime.now().isBefore(_hideGuardUntil)) _hideNow();
  }

  @override
  void onWindowRestore() {
    if (_keepHidden) _hideNow();
  }

  _PortForwardTabPageState(Map<String, dynamic> params) {
    isRDP = params['isRDP'];
    tabController =
        Get.put(DesktopTabController(tabType: DesktopTabType.portForward));
    tabController.onSelected = (id) {
      WindowController.fromWindowId(windowId())
          .setTitle(getWindowNameWithId(id));
    };
    tabController.onRemoved = (_, id) => onRemoveId(id);
    tabController.add(TabInfo(
        key: params['id'],
        label: params['id'],
        selectedIcon: selectedIcon,
        unselectedIcon: unselectedIcon,
        page: PortForwardPage(
          key: ValueKey(params['id']),
          id: params['id'],
          password: params['password'],
          isSharedPassword: params['isSharedPassword'],
          tabController: tabController,
          isRDP: isRDP,
          forceRelay: params['forceRelay'],
          connToken: params['connToken'],
        )));
  }

  @override
  void initState() {
    super.initState();

    windowManager.addListener(this);
    // Decide at WINDOW creation (runs reliably, unlike the inner page on a reconnect):
    // an already-configured tunnel means this opened for a silent reconnect -> hide it
    // and hold it hidden. A peer with no forwards yet is a fresh setup -> stay visible
    // (just no taskbar button, so no hover thumbnail).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await windowManager.setSkipTaskbar(true);
      } catch (_) {}
      if (!isRDP && _peerHasForwards(widget.params['id']?.toString())) {
        _hideReconnectWindow();
      }
    });

    rustDeskWinManager.setMethodHandler((call, fromWindowId) async {
      debugPrint(
          "[Port Forward] call ${call.method} with args ${call.arguments} from window $fromWindowId");
      // for simplify, just replace connectionId
      if (call.method == kWindowEventNewPortForward) {
        final args = jsonDecode(call.arguments);
        final id = args['id'];
        final isRDP = args['isRDP'];
        if (tabController.state.value.tabs.indexWhere((e) => e.key == id) >=
            0) {
          debugPrint("port forward $id exists");
          // Already open -- do NOT steal focus. On a flaky link the forward is
          // re-invoked on every reconnect; popping the window to the front each
          // time is what made the port-forward window feel like spam. If this is a
          // configured tunnel, re-assert hidden in case the reconnect surfaced it.
          if (_keepHidden || (!isRDP && _peerHasForwards(id?.toString()))) {
            _hideReconnectWindow();
          }
          return;
        }
        // New forward tab in an existing window: no taskbar button, and if this peer is
        // already configured (a silent reconnect) keep the whole window hidden.
        try { await windowManager.setSkipTaskbar(true); } catch (_) {}
        if (!isRDP && _peerHasForwards(id?.toString())) _hideReconnectWindow();
        tabController.add(TabInfo(
            key: id,
            label: id,
            selectedIcon: selectedIcon,
            unselectedIcon: unselectedIcon,
            page: PortForwardPage(
              key: ValueKey(args['id']),
              id: id,
              password: args['password'],
              isSharedPassword: args['isSharedPassword'],
              isRDP: isRDP,
              tabController: tabController,
              forceRelay: args['forceRelay'],
              connToken: args['connToken'],
            )));
      } else if (call.method == "onDestroy") {
        tabController.clear();
      } else if (call.method == kWindowActionRebuild) {
        reloadCurrentWindow();
      }
    });
    Future.delayed(Duration.zero, () {
      restoreWindowPosition(WindowType.PortForward, windowId: windowId());
    });
  }

  @override
  Widget build(BuildContext context) {
    final child = Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      body: DesktopTab(
        controller: tabController,
        onWindowCloseButton: () async {
          tabController.clear();
          return true;
        },
        tail: AddButton(),
        selectedBorderColor: MyTheme.accent,
        labelGetter: DesktopTab.tablabelGetter,
      ),
    );
    final tabWidget = isLinux
        ? buildVirtualWindowFrame(
            context,
            Scaffold(
                backgroundColor: Theme.of(context).colorScheme.background,
                body: child),
          )
        : workaroundWindowBorder(
            context,
            Container(
              decoration: BoxDecoration(
                  border: Border.all(color: MyTheme.color(context).border!)),
              child: child,
            ));
    return isMacOS || kUseCompatibleUiMode
        ? tabWidget
        : Obx(
            () => SubWindowDragToResizeArea(
              child: tabWidget,
              resizeEdgeSize: stateGlobal.resizeEdgeSize.value,
              enableResizeEdges: subWindowManagerEnableResizeEdges,
              windowId: stateGlobal.windowId,
            ),
          );
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  void onRemoveId(String id) {
    if (tabController.state.value.tabs.isEmpty) {
      WindowController.fromWindowId(windowId()).close();
    }
  }

  int windowId() {
    return widget.params["windowId"];
  }
}
