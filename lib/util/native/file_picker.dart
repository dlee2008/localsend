import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/apk_picker_page.dart';
import 'package:localsend_app/provider/picking_status_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/theme.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/util/sleep.dart';
import 'package:localsend_app/util/ui/asset_picker_translated_text_delegate.dart';
import 'package:localsend_app/widget/dialogs/loading_dialog.dart';
import 'package:localsend_app/widget/dialogs/message_input_dialog.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:routerino/routerino.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

enum FilePickerOption {
  file(Icons.description),
  folder(Icons.folder),
  media(Icons.image),
  text(Icons.subject),
  app(Icons.apps);

  const FilePickerOption(this.icon);

  final IconData icon;

  String get label {
    switch (this) {
      case FilePickerOption.file:
        return t.sendTab.picker.file;
      case FilePickerOption.folder:
        return t.sendTab.picker.folder;
      case FilePickerOption.media:
        return t.sendTab.picker.media;
      case FilePickerOption.text:
        return t.sendTab.picker.text;
      case FilePickerOption.app:
        return t.sendTab.picker.app;
    }
  }

  /// Returns the options for the current platform.
  static List<FilePickerOption> getOptionsForPlatform() {
    if (checkPlatform([TargetPlatform.iOS])) {
      // On iOS, picking from media is most common.
      // The file app is very limited.
      return [
        FilePickerOption.media,
        FilePickerOption.text,
        FilePickerOption.file,
        FilePickerOption.folder,
      ];
    } else if (checkPlatform([TargetPlatform.android])) {
      // On android, the file app is most powerful.
      return [
        FilePickerOption.file,
        FilePickerOption.media,
        FilePickerOption.text,
        FilePickerOption.folder,
        FilePickerOption.app,
      ];
    } else {
      // Desktop
      return [
        FilePickerOption.file,
        FilePickerOption.folder,
        FilePickerOption.text,
      ];
    }
  }

  Future<void> select({
    required BuildContext context,
    required WidgetRef ref,
  }) async {
    switch (this) {
      case FilePickerOption.file:
        ref.read(pickingStatusProvider.notifier).state = true;
        if (checkPlatform([TargetPlatform.android])) {
          // On android, the files are copied to the cache which takes some time.
          // ignore: unawaited_futures
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => const LoadingDialog(),
          );
        }
        final result = await FilePicker.platform.pickFiles(allowMultiple: true);
        if (result != null) {
          await ref.read(selectedSendingFilesProvider.notifier).addFiles(
                files: result.files,
                converter: CrossFileConverters.convertPlatformFile,
              );
        }
        ref.read(pickingStatusProvider.notifier).state = false;
        break;
      case FilePickerOption.folder:
        ref.read(pickingStatusProvider.notifier).state = true;

        if (checkPlatform([TargetPlatform.android])) {
          try {
            await Permission.manageExternalStorage.request();
          } catch (e) {
            print(e);
          }
        }

        // ignore: use_build_context_synchronously
        if (!context.mounted) {
          return;
        }

        // ignore: unawaited_futures
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const LoadingDialog(),
        );
        await sleepAsync(200); // Wait for the dialog to be shown
        try {
          final directoryPath = await FilePicker.platform.getDirectoryPath();
          if (directoryPath != null) {
            await ref.read(selectedSendingFilesProvider.notifier).addDirectory(directoryPath);
          }
        } catch (e) {
          print(e);
        } finally {
          ref.read(pickingStatusProvider.notifier).state = false;
        }
        break;
      case FilePickerOption.media:
        final oldBrightness = Theme.of(context).brightness;
        final List<AssetEntity>? result = await AssetPicker.pickAssets(
          context,
          pickerConfig: const AssetPickerConfig(maxAssets: 999, textDelegate: TranslatedAssetPickerTextDelegate()),
        );

        WidgetsBinding.instance.addPostFrameCallback((_) async {
          // restore brightness for Android
          await sleepAsync(500);
          if (context.mounted) {
            await updateSystemOverlayStyleWithBrightness(oldBrightness);
          }
        });

        if (result != null) {
          await ref.read(selectedSendingFilesProvider.notifier).addFiles(
                files: result,
                converter: CrossFileConverters.convertAssetEntity,
              );
        }
        break;
      case FilePickerOption.text:
        final result = await showDialog<String>(context: context, builder: (_) => const MessageInputDialog());
        if (result != null) {
          ref.read(selectedSendingFilesProvider.notifier).addMessage(result);
        }
        break;
      case FilePickerOption.app:
        // Currently, only Android APK
        await context.push(() => const ApkPickerPage());
        break;
    }
  }
}
