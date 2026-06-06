import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:ui';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:flangapp_app/enum/action_type.dart';
import 'package:flangapp_app/enum/template.dart';
import 'package:flangapp_app/widgets/app_drawer.dart';
import 'package:flangapp_app/widgets/app_tabs.dart';
import 'package:flangapp_app/widgets/bar.dart';
import 'package:flangapp_app/widgets/downloader.dart';
import 'package:flangapp_app/widgets/error_page.dart';
import 'package:flangapp_app/widgets/loader.dart';
import 'package:flangapp_app/widgets/modal_fit.dart';
import 'package:flangapp_app/widgets/offline_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app.dart';
import '../enum/load_indicator.dart';
import '../models/download_status.dart';
import '../models/navigation_item.dart';
import '../models/web_view_collection.dart';

class WebView extends StatefulWidget {
  final String? playerID;

  const WebView({Key? key, this.playerID}) : super(key: key);

  @override
  _WebViewState createState() => _WebViewState();
}

class _WebViewState extends State<WebView> {

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey();

  final ReceivePort _port = ReceivePort();

  bool isOffline = false;

  // current tab index
  int tabIndex = 0;
  // history
  int historyIndex = 0;
  // web views collections
  List<WebViewCollection> webViewsCollections = [];
  // download file
  DownloadItem download =  DownloadItem(
    status: false,
    filename: "",
    progress: 0
  );
  // active link
  String activeLink = "";
  // wev view options
  InAppWebViewSettings settings = InAppWebViewSettings(
      useShouldOverrideUrlLoading: true,
      mediaPlaybackRequiresUserGesture: true,
      supportZoom: false,
      useOnDownloadStart: true,
      horizontalScrollBarEnabled: false,
      userAgent: Config.userAgent,
      geolocationEnabled: true,
      allowsInlineMediaPlayback: true,
  );

  /// *** Init view screen *** ///
  @override
  void initState() {
    activeLink = Config.appLink;
    initWebViewCollections();
    initPullToRefresh();
    super.initState();
    Connectivity().onConnectivityChanged.
      listen((ConnectivityResult result) {
        debugPrint("Change network connection status");
        changeConnectionStatus(result);
      });
    _bindBackgroundIsolate();
    _getAccess();
  }

  @override
  void dispose() {
    _unbindBackgroundIsolate();
    super.dispose();
  }

  Future<void> _getAccess() async {
    if (Platform.isAndroid) {
      if (Config.accessCamera) {
        await Permission.camera.request();
      }
      if (Config.accessMicrophone) {
        await Permission.microphone.request();
      }
    }
  }

  void _bindBackgroundIsolate() {
    bool isSuccess = IsolateNameServer.registerPortWithName(
        _port.sendPort, 'downloader_send_port');
    if (!isSuccess) {
      _unbindBackgroundIsolate();
      _bindBackgroundIsolate();
      return;
    }
    _port.listen((dynamic data) {
      String? id = data[0];
      DownloadTaskStatus? status = data[1];
      int progress = data[2];
      if (progress == 100) {
        setState(() {
          download.progress = 0;
          download.status = false;
        });
        return;
      }
      setState(() {
        download.progress = progress;
        download.status = true;
      });
      debugPrint("id - $id");
      debugPrint("status - ${status.toString()}");
      debugPrint("progress - $progress");
    });
  }

  void _unbindBackgroundIsolate() {
    IsolateNameServer.removePortNameMapping('downloader_send_port');
  }

  void initWebViewCollections() {
    if (Config.appTemplate == Template.tabs) {
      List<NavigationItem> _items = Config.mainNavigation;
      webViewsCollections = [
        for (var i = 0; i < _items.length; i ++)
          if (_items[i].type == ActionType.internal)
            WebViewCollection(
              url: _items[i].value.toString(),
              isLoading: true,
              title: Config.appName,
              error: false
            )
      ];
    } else {
      webViewsCollections = [
        WebViewCollection(
          url: Config.appLink,
          isLoading: true,
          title: Config.appName,
          error: false
        )
      ];
    }
  }

  Future<bool> canJumpBack() async {
    try {
      if (webViewsCollections[tabIndex]
          .webExplorerController != null
      ) {
        if (await webViewsCollections[tabIndex]
            .webExplorerController!
            .canGoBack()) {
          return true;
        } else {
          return false;
        }
      }
    } catch (e) {
      return false;
    }
    return false;
  }

  void initPullToRefresh() {
    if (Config.appTemplate != Template.tabs) {
      webViewsCollections[0].pullToRefreshController = PullToRefreshController(
        settings: PullToRefreshSettings(
          color: Colors.grey,
        ),
        onRefresh: () async {
            if (Platform.isAndroid) {
              webViewsCollections[0].webExplorerController?.reload();
            } else {
              webViewsCollections[0].webExplorerController?.loadUrl(
                  urlRequest: URLRequest(
                      url: await webViewsCollections[0]
                          .webExplorerController?.getUrl()
                  )
              );
            }
        },
      );
      return;
    }
    List<NavigationItem> _items = Config.mainNavigation;
    for (var i = 0; i < _items.length; i ++) {
      if (_items[i].type == ActionType.internal) {
        webViewsCollections[i].pullToRefreshController = PullToRefreshController(
          settings: PullToRefreshSettings(
            color: Colors.black,
          ),
          onRefresh: () async {
            if (Platform.isAndroid) {
              webViewsCollections[i].webExplorerController?.reload();
            } else {
              webViewsCollections[i].webExplorerController?.loadUrl(
                  urlRequest: URLRequest(
                      url: await webViewsCollections[i]
                          .webExplorerController?.getUrl()
                  )
              );
            }
          },
        );
      }
    }
  }

  void navigationAction(NavigationItem item) async {
    if (item.type == ActionType.internal) {
      webViewsCollections[tabIndex].webExplorerController?.loadUrl(
          urlRequest: URLRequest(url: WebUri(item.value))
      );
    } else if (item.type == ActionType.external) {
      final Uri url = Uri.parse(item.value);
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } else if (item.type == ActionType.email) {
      final Uri email = Uri.parse("mailto:${item.value}");
      if (await canLaunchUrl(email)) {
        await launchUrl(email, mode: LaunchMode.externalApplication);
      }
    } else if (item.type == ActionType.phone) {
      final Uri phone = Uri.parse("tel:+${item.value}");
      if (await canLaunchUrl(phone)) {
        await launchUrl(phone, mode: LaunchMode.externalApplication);
      }
    } else if (item.type == ActionType.share) {
      Share.share(
          "${webViewsCollections[tabIndex].title} ${webViewsCollections[tabIndex].url}"
      );
    } else if (item.type == ActionType.openModal) {
      _openModalNavigation(item.name);
    }
  }

  void injectCss(index) {
    StringBuffer styles = StringBuffer();
    for (var item in Config.cssHideBlock) {
      styles.write("$item{ display: none; }");
    }
    webViewsCollections[index].webExplorerController?.injectCSSCode(
        source: styles.toString()
    );
  }

  void changeConnectionStatus(ConnectivityResult result) async {
    if (result == ConnectivityResult.none) {
      setState(() {
        isOffline = true;
      });
    } else {
      setState(() {
        isOffline = false;
      });
    }
  }

  String _getHashPlayer() {
    var bytes = utf8.encode(widget.playerID.toString());
    var key = utf8.encode(Config.osSigning);
    var hmacSha256 = Hmac(sha256, key);
    var digest = hmacSha256.convert(bytes);
    return digest.toString();
  }

  Future<bool> _onBackPressed() async {
    return await showDialog(
      context: context, builder: (context) => AlertDialog(
      title: Text(Config.titleExit),
      content: Text(Config.messageExit),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(Config.actionNoDownload),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(true);
          },
          child: Text(Config.actionYesDownload),
        ),
      ],
    ));
  }

  Future<bool> checkStoragePermission() async {
    if (Platform.isAndroid) {
      final status = await Permission.storage.status;
      if (status != PermissionStatus.granted) {
        final result = await Permission.storage.request();
        if (result == PermissionStatus.granted) {
          return true;
        }
      } else {
        return true;
      }
    } else {
      return true;
    }
    return false;
  }

  void _openModalNavigation(String title) {
    showCupertinoModalBottomSheet(
      context: context,
      builder: (context) => ModalFit(
        title: title,
        onAction: (NavigationItem item) {
          navigationAction(item);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        bool status = await canJumpBack();
        if (status) {
          webViewsCollections[tabIndex].webExplorerController?.goBack();
        } else {
          final shouldExit = await _onBackPressed();
          if (shouldExit) {
            SystemNavigator.pop();
          }
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
        resizeToAvoidBottomInset: false,
        appBar: Config.appTemplate != Template.blank ? Bar(
          title: webViewsCollections[tabIndex].title,
          canBack: canJumpBack(),
          onBack: () => webViewsCollections[tabIndex]
              .webExplorerController?.goBack(),
          onDrawer: () => _scaffoldKey.currentState!.openDrawer(),
          onAction: (NavigationItem item) {
            navigationAction(item);
          },
        ) : null,
        body: SafeArea(
          top: Config.appTemplate == Template.blank
              ? true : false,
          bottom: Config.appTemplate == Template.blank
              ? true : false,
          child: !isOffline ? IndexedStack(
            index: tabIndex,
            children: [
              for (var i = 0; i < webViewsCollections.length; i ++)
                _webBrowser(i),
            ],
          ) : const OfflinePage(),
        ),
        drawer: AppDrawer(
          activeLink: webViewsCollections[tabIndex].url,
          onAction: (NavigationItem item) {
            navigationAction(item);
          },
        ),
        drawerEdgeDragWidth: 0,
        bottomNavigationBar: Config.appTemplate == Template.tabs ? AppTabs(
          currentIndex: tabIndex,
          onTabChange: (index) {
            setState(() {
              tabIndex = index;
            });
          },
        ) : null,
      ),
    );
  }

  Widget _webBrowser(int index) {
    Size size = MediaQuery.of(context).size;
    return Stack(
      fit: StackFit.expand,
      children: [
        InAppWebView(
          initialUrlRequest: URLRequest(
            url: WebUri(webViewsCollections[index].url),
            headers: {
              'Sn-Player-Id': widget.playerID.toString(),
              'Sn-Player-Sign' : _getHashPlayer()
            },
          ),
          initialSettings: settings,
          pullToRefreshController: Config.pullToRefresh
              ? webViewsCollections[index].pullToRefreshController
              : null,
          onWebViewCreated: (InAppWebViewController controller) {
            webViewsCollections[index].webExplorerController = controller;
          },
          onLoadStart: (controller, url) {
            setState(() {
              webViewsCollections[index].url = url.toString();
              webViewsCollections[index].isLoading = true;
              activeLink = url.toString();
            });
          },
          onGeolocationPermissionsShowPrompt: (InAppWebViewController controller, String origin) async {
            await Permission.location.request();
            return Future.value(GeolocationPermissionShowPromptResponse(origin: origin, allow: true, retain: true));
          },
          shouldOverrideUrlLoading: (controller, navigationAction) async {
            var uri = navigationAction.request.url!;

            // Security: Prevent local file inclusion and XSS via specific schemes.
            if (["file", "javascript", "data"].contains(uri.scheme)) {
              return NavigationActionPolicy.CANCEL;
            }

            if (![ "http", "https", "about"].contains(uri.scheme)) {
              String url = uri.toString();
              final parsedUri = Uri.parse(url);
              if (await canLaunchUrl(parsedUri)) {
                // Launch the App
                await launchUrl(
                  parsedUri, mode: LaunchMode.externalApplication
                );
                return NavigationActionPolicy.CANCEL;
              }
            }
            return NavigationActionPolicy.ALLOW;
          },
          onProgressChanged: (controller, progress) {
            injectCss(index);
            if (progress == 100) {
              webViewsCollections[index].pullToRefreshController?.endRefreshing();
              setState(() {
                webViewsCollections[index].isLoading = false;
              });
              if (Config.displayTitle) {
                controller.getTitle().then((value) {
                  if (value != null) {
                    setState(() {
                      webViewsCollections[index].title = value;
                    });
                  }
                });
              }
            }
          },
          onPermissionRequest:
              (InAppWebViewController controller, PermissionRequest permissionRequest) async {
            final String origin = permissionRequest.origin.toString();
            final String originHost = Uri.tryParse(origin)?.host ?? '';
            final String appLinkHost = Uri.tryParse(Config.appLink)?.host ?? '';
            final List<String> allowedHosts = [appLinkHost];

            for (var item in Config.mainNavigation) {
              if (item.type == ActionType.internal) {
                 final host = Uri.tryParse(item.value)?.host;
                 if (host != null) allowedHosts.add(host);
              }
            }
            for (var item in Config.modalNavigation) {
              if (item.type == ActionType.internal) {
                 final host = Uri.tryParse(item.value)?.host;
                 if (host != null) allowedHosts.add(host);
              }
            }

            if (!allowedHosts.contains(originHost)) {
              return PermissionResponse(
                  resources: permissionRequest.resources,
                  action: PermissionResponseAction.DENY);
            }

            return PermissionResponse(
                resources: permissionRequest.resources,
                action: PermissionResponseAction.GRANT);
          },
          onDownloadStartRequest: (controller, downloadStartRequest) async {
            final Uri url = downloadStartRequest.url;
            checkStoragePermission().then((hasGranted) async {
              if (hasGranted == true) {
                String _localPath;
                if (Platform.isIOS) {
                  final dir = await getApplicationDocumentsDirectory();
                  _localPath = dir.path;
                } else {
                  final dir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
                  _localPath = dir.path;
                }
                final dir = Directory(_localPath);
                if (!await dir.exists()) {
                  await dir.create(recursive: true);
                }
                await FlutterDownloader.enqueue(
                  url: url.toString(),
                  savedDir: _localPath,
                  showNotification: true,
                  openFileFromNotification: true,
                  requiresStorageNotLow: true,
                );
              }
            });
          },
          onReceivedError: (controller, WebResourceRequest request, WebResourceError error) {
            webViewsCollections[index].pullToRefreshController?.endRefreshing();
            if (error.type.toNativeValue() == -999 || error.type.toNativeValue() == -1) {
              return;
            }
            if (error.description.isNotEmpty) {
              setState(() {
                webViewsCollections[index].isLoading = false;
                webViewsCollections[index].error = true;
              });
              debugPrint("Fail load page message - ${error.description}");
            }
          },
          onReceivedHttpError: (controller, WebResourceRequest request, WebResourceResponse errorResponse) {
            webViewsCollections[index].pullToRefreshController?.endRefreshing();
            if (errorResponse.statusCode != null && errorResponse.statusCode! >= 400) {
              setState(() {
                webViewsCollections[index].isLoading = false;
                webViewsCollections[index].error = true;
              });
            }
          },
        ),
        if (webViewsCollections[index].error)
          ErrorPage(
            onBack: () {
              setState(() {
                webViewsCollections[index].error = false;
              });
            },
          ),
        if (Config.indicator != LoadIndicator.none)
          Loader(
            color: Config.indicatorColor,
            isSpinner: Config.indicator == LoadIndicator.spinner,
            width: size.width,
            isDisplay: webViewsCollections[index].isLoading
          ),
        if (download.status)
          Downloader(
            filename: download.filename,
            progress: download.progress,
          )
      ],
    );
  }

}