import 'package:url_launcher/url_launcher.dart';

void openWebmail(String user, String pass) {
  launchUrl(
    Uri.parse('https://webmail.sisol.com.mx'),
    mode: LaunchMode.externalApplication,
  );
}
