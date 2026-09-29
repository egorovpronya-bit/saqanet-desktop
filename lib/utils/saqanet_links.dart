import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/utils/uri_utils.dart';

/// Opens the SAQANet support bot, preferring the in-app Telegram deep link
/// and falling back to the https link when Telegram isn't installed.
Future<void> openSaqanetBot() async {
  final opened = await UriUtils.tryLaunch(Uri.parse(Constants.telegramBotDeepLink));
  if (!opened) {
    await UriUtils.tryLaunch(Uri.parse(Constants.telegramChannelUrl));
  }
}
