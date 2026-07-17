import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';

/// PIN lock for the RemoteX app itself.
///
/// Without this, anyone with physical access to an unlocked machine can open
/// RemoteX and connect to every saved peer.
///
/// This deliberately reuses the existing unlock PIN (Settings -> Security ->
/// PIN, `bind.mainGetUnlockPin()`), which already gated the settings pages,
/// rather than introducing a second PIN. One PIN, set in one place, now guards
/// both the settings and the app itself.
///
/// Locking happens once, at launch -- not on minimise or idle.
///
/// Recovery: if the PIN is forgotten, clear the `unlock-pin` entry from the
/// config (or run `RemoteX.exe --set-unlock-pin ""` as admin). An app-level PIN
/// cannot defend against someone who already has file access, and permanently
/// locking a user out of their own machine would be worse.
class AppLock {
  AppLock._();

  /// Whether the correct PIN has been entered during this run of the app.
  static bool unlocked = false;

  static String _pin() {
    try {
      return bind.mainGetUnlockPin();
    } catch (_) {
      return '';
    }
  }

  /// True when a PIN has been configured.
  static bool get isEnabled => _pin().isNotEmpty;

  /// True when the lock screen should be shown right now.
  static bool get shouldLock => isEnabled && !unlocked;

  static bool verify(String pin) {
    final correct = _pin();
    return correct.isNotEmpty && pin == correct;
  }
}

/// Full-window lock screen shown at launch while a PIN is set.
class AppLockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;

  const AppLockScreen({Key? key, required this.onUnlocked}) : super(key: key);

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final pin = _controller.text;
    if (pin.isEmpty) return;
    if (AppLock.verify(pin)) {
      AppLock.unlocked = true;
      widget.onUnlocked();
    } else {
      setState(() => _error = translate('Wrong PIN'));
      _controller.clear();
      _focus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: 56, child: loadLogo()),
                const SizedBox(height: 24),
                Icon(Icons.lock_outline_rounded,
                    size: 32, color: MyTheme.accent),
                const SizedBox(height: 10),
                Text(
                  translate('Enter your PIN to unlock'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _controller,
                  focusNode: _focus,
                  obscureText: true,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onSubmitted: (_) => _submit(),
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  decoration: InputDecoration(
                    hintText: translate('PIN'),
                    errorText: _error,
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submit,
                    child: Text(translate('Unlock')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
