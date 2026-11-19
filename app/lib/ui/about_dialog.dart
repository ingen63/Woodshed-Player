// «About Woodshed Player» (#50/AK6): version, licence and links to privacy policy and terms (open in the browser).
import 'package:material_ui/material_ui.dart';

import '../app/app_info.dart';
import '../app/file_platform.dart';
import 'messages.dart';

Future<void> showAbout(BuildContext context, FilePlatform files) {
  final l = context.l10n;
  Widget link(Key key, String label, String url) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton(
      key: key,
      style: TextButton.styleFrom(padding: EdgeInsets.zero),
      onPressed: () => files.openUrl(url),
      child: Text(label),
    ),
  );
  return showDialog<void>(
    context: context,
    builder: (context) => AboutDialog(
      applicationName: 'Woodshed Player',
      applicationVersion: l.aboutVersion(appVersion),
      applicationLegalese: l.aboutLicense,
      children: [
        const SizedBox(height: 12),
        link(const Key('aboutPrivacy'), l.privacyPolicy, privacyUrl),
        link(const Key('aboutTerms'), l.termsOfUse, termsUrl),
        link(const Key('aboutSource'), l.sourceCode, repositoryUrl),
      ],
    ),
  );
}
