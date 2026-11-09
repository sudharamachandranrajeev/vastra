import 'dart:convert';
import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../domain/page_capture.dart';
import '../domain/product_importer.dart';
import '../domain/shops.dart';
import 'paper.dart';

/// Saves what the browser shows and returns a short message for the owner.
typedef SavePage = Future<String> Function(ScreenCapture capture);

/// Opens a shop page in Vastra's own browser.
typedef OpenShop = Future<void> Function(BuildContext context, Uri start, SavePage onSave);

/// Vastra's browser. The owner can sign in to any shop; the shop keeps its own
/// sign-in in the browser's storage on this device, and Vastra never sees
/// passwords. On Android it opens inside the app; on Windows and Linux it is
/// a separate window with a "Save to Vastra" button in its corner.
Future<void> openShop(BuildContext context, Uri start, SavePage onSave) {
  if (Platform.isAndroid || Platform.isIOS) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EmbeddedShopBrowser(start: start, onSave: onSave),
      ),
    );
  }
  return _openWindow(start, onSave);
}

/// Forgets every shop sign-in, cookie and stored page data in Vastra's browser.
Future<void> signOutOfShops() async {
  if (Platform.isAndroid || Platform.isIOS) {
    await WebViewCookieManager().clearCookies();
    final controller = WebViewController();
    await controller.clearLocalStorage();
    await controller.clearCache();
    return;
  }
  await _window?.close();
  _window = null;
  await WebviewWindow.clearAll(windows: await _windowsOptions());
}

Future<String> _save(Object? raw, SavePage onSave) async {
  try {
    return await onSave(ScreenCapture.fromResult(raw));
  } on ImportFailure catch (e) {
    return e.message;
  } on FormatException catch (e) {
    return e.message;
  } on Object {
    return 'Vastra could not read this page.';
  }
}

// ---- Windows and Linux: one shop window ----

Webview? _window;
SavePage? _onSave;

Future<WindowsWebviewOptions> _windowsOptions() async => WindowsWebviewOptions(
  userDataFolder: path.join((await getApplicationSupportDirectory()).path, 'WebView2'),
  denyCameraAndMicrophone: true,
);

/// A floating button the shop window shows on every page. It only asks
/// Vastra to read the page; Vastra does the reading itself.
const saveButtonScript = r'''(() => {
  if (window.top !== window || window.__vastraButton) return;
  window.__vastraButton = true;
  const add = () => {
    if (!document.body) return setTimeout(add, 200);
    const host = document.createElement('div');
    host.style.cssText = 'position:fixed;right:16px;bottom:16px;z-index:2147483647';
    const root = host.attachShadow({mode: 'closed'});
    root.innerHTML = '<style>button{font:600 14px system-ui,sans-serif;padding:10px 18px;border:0;border-radius:22px;background:#9a5b2e;color:#fff;box-shadow:0 4px 14px rgba(0,0,0,.25);cursor:pointer}p{font:13px system-ui,sans-serif;background:#fffaf2;color:#2b2420;padding:8px 12px;border-radius:10px;margin:0 0 8px;max-width:280px;box-shadow:0 2px 8px rgba(0,0,0,.2)}</style><p hidden></p><button type="button">Save to Vastra</button>';
    const note = root.querySelector('p'), button = root.querySelector('button');
    button.onclick = () => {
      button.disabled = true;
      button.textContent = 'Saving…';
      window.desktopWebview.postMessage('vastraSave', null);
    };
    window.__vastraSaved = (message) => {
      button.disabled = false;
      button.textContent = 'Save to Vastra';
      note.textContent = message;
      note.hidden = false;
      setTimeout(() => { note.hidden = true; }, 6000);
    };
    document.documentElement.appendChild(host);
  };
  add();
})()''';

Future<void> _openWindow(Uri start, SavePage onSave) async {
  _onSave = onSave;
  final open = _window;
  if (open != null) {
    await open.launch(start.toString());
    return;
  }
  final w = await WebviewWindow.create(
    configuration: CreateConfiguration(
      title: 'Vastra · shop',
      windowWidth: 1200,
      windowHeight: 860,
      windows: await _windowsOptions(),
    ),
  );
  _window = w;
  w.onClose.then((_) {
    if (identical(_window, w)) _window = null;
  });
  await w.setOnUrlRequestCallback(browsable);
  await w.addScriptToExecuteOnDocumentCreated(saveButtonScript);
  var busy = false;
  w.addJavaScriptHandler('vastraSave', (_, _) async {
    if (busy) return;
    busy = true;
    try {
      final message = await _save(await w.evaluateJavaScript(captureScript), _onSave ?? onSave);
      await w.evaluateJavaScript('window.__vastraSaved && window.__vastraSaved(${jsonEncode(message)})');
    } on Object {
      // The window closed while saving.
    } finally {
      busy = false;
    }
  });
  await w.launch(start.toString());
}

// ---- Android: inside the app ----

class EmbeddedShopBrowser extends StatefulWidget {
  const EmbeddedShopBrowser({super.key, required this.start, required this.onSave});
  final Uri start;
  final SavePage onSave;
  @override
  State<EmbeddedShopBrowser> createState() => _EmbeddedShopBrowserState();
}

class _EmbeddedShopBrowserState extends State<EmbeddedShopBrowser> {
  late String _url = widget.start.toString();
  bool _loading = true, _saving = false;
  late final WebViewController _controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (r) =>
            browsable(r.url) ? NavigationDecision.navigate : NavigationDecision.prevent,
        onPageStarted: (url) => setState(() {
          _url = url;
          _loading = true;
        }),
        onPageFinished: (url) => setState(() {
          _url = url;
          _loading = false;
        }),
      ),
    )
    ..loadRequest(widget.start);

  Future<void> _savePage() async {
    setState(() => _saving = true);
    Object? raw;
    try {
      raw = await _controller.runJavaScriptReturningResult(captureScript);
    } on Object {
      raw = null;
    }
    final message = await _save(raw, widget.onSave);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop) return;
      if (await _controller.canGoBack()) {
        await _controller.goBack();
      } else if (context.mounted) {
        Navigator.of(context).pop();
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(Uri.tryParse(_url)?.host ?? '', style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(tooltip: 'Reload', icon: const Icon(Icons.refresh), onPressed: _controller.reload),
          IconButton(
            tooltip: 'Close shop browser',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
        bottom: _loading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: WebViewWidget(controller: _controller),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Tone.copper,
        foregroundColor: Colors.white,
        onPressed: _saving ? null : _savePage,
        icon: const Icon(Icons.bookmark_add_outlined),
        label: Text(_saving ? 'Saving…' : 'Save to Vastra'),
      ),
    ),
  );
}
