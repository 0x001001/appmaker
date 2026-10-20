class DownloadItem {
  bool status;
  String filename;
  int progress;

  DownloadItem({
    this.status = false,
    this.filename = "",
    this.progress = 0
  });
}