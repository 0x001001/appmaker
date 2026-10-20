import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class WebViewCollection {
  InAppWebViewController? webExplorerController;
  PullToRefreshController? pullToRefreshController;
  String url;
  bool isLoading;
  String title;
  bool error;

  WebViewCollection({
    this.webExplorerController,
    this.pullToRefreshController,
    required this.url,
    required this.isLoading,
    required this.title,
    required this.error
  });

}