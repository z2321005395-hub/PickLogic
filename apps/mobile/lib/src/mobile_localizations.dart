import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

final class MobileLocalizations {
  const MobileLocalizations(this.locale);

  final Locale locale;

  static const LocalizationsDelegate<MobileLocalizations> delegate =
      _MobileLocalizationsDelegate();

  static MobileLocalizations of(BuildContext context) =>
      Localizations.of<MobileLocalizations>(context, MobileLocalizations) ??
      const MobileLocalizations(Locale('en'));

  static const Map<String, Map<String, String>> _values = {
    'en': {
      'switchLanguage': '切换到中文',
      'bootstrapTitle': 'Local platform features are unavailable',
      'bootstrapBody':
          'PickLogic has not read any media or files. Retry or restart the app.',
      'retryBootstrap': 'Retry local setup',
      'permissionError':
          'The media permission check did not finish; no media or files were read.',
      'safSaved':
          'Read-only folder access was saved; no file was moved or modified.',
      'safDenied': 'Read-only folder access was not granted.',
      'filesTitle': 'File collections',
      'filesDescription':
          'Only one MediaStore metadata page is read at a time. Use read-only SAF access for other shared folders.',
      'documents': 'Documents',
      'downloads': 'Downloads',
      'chooseSafReadOnly': 'Choose accessible folder (SAF, read-only)',
      'lazyLoad': 'Content loads on demand after opening this page.',
      'collectionUnavailable':
          'This collection is not accessible. Choose a shared folder with SAF instead.',
      'emptyCollection': 'No accessible items on this page.',
      'screenshotsTitle': 'Screenshots',
      'screenshotPermissionDetail':
          'After permission, only MediaStore metadata and bounded thumbnails for visible items are read. OCR is not automatic.',
      'screenshotLazy': 'Screenshots load on demand after opening this page.',
      'screenshotError': 'The screenshot collection is unavailable.',
      'screenshotEmpty': 'No accessible screenshots.',
      'screenshotCount':
          '{total} accessible screenshots · showing the latest {visible} (newest first)',
      'groupNote':
          'Consecutive groups use time and source clues; a clue is not proof of app ownership.',
      'allMonths': 'All months',
      'reviewSummary':
          'Local review: Keep {keep} · Later {later} · Delete review {delete}',
      'reviewSafety':
          'These are session-local markers. Delete review never deletes, moves, or renames media.',
      'single': 'Single',
      'consecutive': '{count} consecutive',
      'sourceClue': 'Source clue: {source}',
      'localMarker': 'Local marker: {state} · OCR: not requested',
      'markerSaved':
          '{state} · saved only as a local review marker; the original file was not modified',
      'keep': 'Keep',
      'later': 'Later',
      'deleteReview': 'Delete review',
      'protected': 'Protected',
      'unreviewed': 'Unreviewed',
      'photosTitle': 'Photos',
      'photosNoAccess': 'PickLogic does not read photos without permission.',
      'photosLazy': 'Photos load on demand after opening this page.',
      'photosDescription':
          'Search metadata on the current page. Thumbnails load only when visible.',
      'photosSearchHint': 'Search photo name or type',
      'photosError': 'The photo collection is unavailable.',
      'photosNoMatches': 'No matching photos on this page.',
      'storageTitle': 'Storage Insight',
      'storageLoading': 'Reading the aggregate storage summary…',
      'accessible': 'Accessible',
      'restricted': 'Restricted',
      'volumeUsed': 'Device data volume used (system aggregate)',
      'volumeDetail': '{used} / {total}; cannot be attributed to files or apps',
      'sharedMedia': 'Visible shared-media scope',
      'selectedVisualOnly': 'Only user-selected photos and videos',
      'authorizedCollections': 'Only authorized MediaStore collections',
      'notAuthorized': 'Not authorized',
      'downloadStorage': 'Downloads, installers, and archives',
      'mediaStoreSafOnly': 'Only MediaStore/SAF-visible items',
      'safRequired': 'Choose a folder with SAF',
      'metadataQueue': 'Background incremental metadata queue',
      'queuePersistent':
          'Indexed {items}; completed {done}; failed {failed}; SQLite checkpoint resumes; OCR is not scheduled',
      'queueSession':
          'Indexed {items}; completed {done}; current session only; OCR is not scheduled',
      'pauseIndex': 'Pause indexing',
      'resumeIndex': 'Resume indexing',
      'checkNew': 'Check new content',
      'privateData': 'Other apps’ private data',
      'platformRestriction': 'Platform restriction',
      'explicitLimits': 'Explicit limits',
      'limitPlatform':
          'Android does not let third-party apps inspect this area directly.',
      'limitAggregate':
          'System aggregates include data PickLogic cannot enumerate or attribute.',
      'limitPrivate':
          'Other apps’ private folders are not read or estimated, and no cleanup action is offered.',
      'limitBounded':
          'Only paged metadata is processed; thumbnails load on demand when visible.',
      'limitDownloads':
          'Downloads and documents are visible only through MediaStore or user-selected SAF folders.',
      'safStorageNote':
          'SAF can expose a user-selected shared folder. Any media operation still requires a separate preview and confirmation.',
      'permissionMissing': 'Media read permission has not been granted.',
      'permissionSafety':
          'The first screen remains usable; PickLogic never bypasses Android scoped storage.',
      'selectMedia': 'Choose media permissions',
      'selectFolder': 'Choose shared folder',
      'searchField': 'Search by name, type, or category',
      'searchMinimum':
          'Enter at least two characters; only local metadata is searched.',
      'indexUnavailable': 'The local index is unavailable.',
      'noSearchResults': 'No matching results.',
      'insightTitle': 'Insight',
      'insightSummary': 'Local metadata identifies this as a {type} item.',
      'type': 'Type',
      'risk': 'Risk',
      'reviewRisk': 'Review',
      'confidence': 'Confidence',
      'bytes': 'Bytes',
      'captured': 'Captured',
      'source': 'Source',
      'metadataEvidence':
          'Evidence: local metadata only; no full-file analysis was requested.',
      'open': 'Open',
      'opened': 'Sent to the system viewer',
      'noViewer': 'No compatible viewer is available',
    },
    'zh': {
      'switchLanguage': 'Switch to English',
      'bootstrapTitle': '本地平台能力暂时不可用',
      'bootstrapBody': 'PickLogic 未读取任何媒体或文件。请重试；若仍失败，请重新启动应用。',
      'retryBootstrap': '重试本地初始化',
      'permissionError': '媒体权限检查未完成；PickLogic 未读取任何媒体或文件。',
      'safSaved': '目录只读授权已保存；未移动或修改任何文件。',
      'safDenied': '未获得目录只读授权。',
      'filesTitle': '文件集合',
      'filesDescription': '每次只读取一页 MediaStore 元数据；其他共享目录使用 SAF 只读授权。',
      'documents': '文档',
      'downloads': '下载',
      'chooseSafReadOnly': '选择可访问目录（SAF，只读）',
      'lazyLoad': '进入页面后按需加载。',
      'collectionUnavailable': '此集合当前不可访问；可改用 SAF 选择共享目录。',
      'emptyCollection': '当前页没有可访问项目。',
      'screenshotsTitle': '截图',
      'screenshotPermissionDetail': '授权后只读取 MediaStore 元数据与可见项的有界缩略图；不会自动 OCR。',
      'screenshotLazy': '进入截图页后按需加载。',
      'screenshotError': '当前无法读取截图集合。',
      'screenshotEmpty': '没有可访问截图。',
      'screenshotCount': '共 {total} 张可访问截图 · 当前显示最近 {visible} 张（日期倒序）',
      'groupNote': '按时间与来源线索连续分组；来源线索不是应用归属结论。',
      'allMonths': '全部月份',
      'reviewSummary': '本地审查队列：保留 {keep} · 稍后 {later} · 删除审查 {delete}',
      'reviewSafety': '这些是当前会话的本地标记；删除审查不会删除、移动或重命名媒体。',
      'single': '单张',
      'consecutive': '连续 {count} 张',
      'sourceClue': '来源线索：{source}',
      'localMarker': '本地标记：{state} · OCR：未请求',
      'markerSaved': '{state} · 仅保存为本地审查标记，未修改原文件',
      'keep': '保留',
      'later': '稍后',
      'deleteReview': '删除审查',
      'protected': '已保护',
      'unreviewed': '尚未判断',
      'photosTitle': '照片',
      'photosNoAccess': '未授权时 PickLogic 不读取照片。',
      'photosLazy': '进入照片页后按需加载。',
      'photosDescription': '当前页元数据搜索；缩略图只在可见时按需读取。',
      'photosSearchHint': '搜索照片名称或类型',
      'photosError': '当前无法读取照片集合。',
      'photosNoMatches': '当前页没有匹配照片。',
      'storageTitle': '存储知件',
      'storageLoading': '正在读取系统存储摘要…',
      'accessible': '可访问',
      'restricted': '受限',
      'volumeUsed': '设备数据卷已用空间（系统聚合）',
      'volumeDetail': '{used} / {total}；不可据此归因到文件或应用',
      'sharedMedia': '共享媒体可见范围',
      'selectedVisualOnly': '仅限用户选择的照片和视频',
      'authorizedCollections': '仅限已授权的 MediaStore 集合',
      'notAuthorized': '尚未授权，无法检查',
      'downloadStorage': '下载、安装包与压缩包',
      'mediaStoreSafOnly': '仅统计 MediaStore/SAF 可见项',
      'safRequired': '需要用户通过 SAF 选择目录',
      'metadataQueue': '后台增量元数据队列',
      'queuePersistent':
          '已索引 {items} 项；完成 {done} 批；失败 {failed} 批；SQLite 检查点可恢复；不调度 OCR',
      'queueSession': '已索引 {items} 项；完成 {done} 批；当前会话状态；不调度 OCR',
      'pauseIndex': '暂停索引',
      'resumeIndex': '继续索引',
      'checkNew': '检查新增内容',
      'privateData': '其他应用私有数据',
      'platformRestriction': '平台限制',
      'explicitLimits': '明确限制',
      'limitPlatform': '当前 Android 权限不允许第三方应用直接检查该部分。',
      'limitAggregate': '系统聚合值包含 PickLogic 无法枚举或归因的数据。',
      'limitPrivate': '不读取其他应用私有目录，不估算其内容，不提供清理按钮。',
      'limitBounded': '仅处理按页返回的元数据；缩略图在可见时按需读取。',
      'limitDownloads': '下载和文档仅在 MediaStore 或用户选择的 SAF 范围内可见。',
      'safStorageNote': '可使用 SAF 查看用户明确选择的共享目录；任何媒体操作仍需另行预览与确认。',
      'permissionMissing': '尚未获得媒体只读权限。',
      'permissionSafety': '首屏保持可用；不会在后台绕过 Android scoped storage。',
      'selectMedia': '选择媒体权限',
      'selectFolder': '选择共享目录',
      'searchField': '按名称、类型或分类搜索',
      'searchMinimum': '输入至少两个字符；仅搜索本地元数据。',
      'indexUnavailable': '当前索引不可访问。',
      'noSearchResults': '没有匹配结果。',
      'insightTitle': '知件',
      'insightSummary': '本地元数据将此项目识别为 {type}。',
      'type': '类型',
      'risk': '风险',
      'reviewRisk': '需审查',
      'confidence': '置信度',
      'bytes': '字节',
      'captured': '时间',
      'source': '来源',
      'metadataEvidence': '证据：仅使用本地元数据；未请求整文件分析。',
      'open': '打开',
      'opened': '已交给系统打开',
      'noViewer': '没有可用的打开方式',
    },
  };

  String text(String key) =>
      _values[locale.languageCode]?[key] ?? _values['en']![key] ?? key;

  String format(String key, Map<String, Object> values) {
    var result = text(key);
    for (final entry in values.entries) {
      result = result.replaceAll('{${entry.key}}', '${entry.value}');
    }
    return result;
  }
}

final class _MobileLocalizationsDelegate
    extends LocalizationsDelegate<MobileLocalizations> {
  const _MobileLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'en' || locale.languageCode == 'zh';

  @override
  Future<MobileLocalizations> load(Locale locale) =>
      SynchronousFuture(MobileLocalizations(locale));

  @override
  bool shouldReload(_MobileLocalizationsDelegate old) => false;
}
