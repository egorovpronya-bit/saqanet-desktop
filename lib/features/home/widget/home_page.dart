import 'package:dartx/dartx.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/localization/locale_extensions.dart';
import 'package:hiddify/core/localization/locale_preferences.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/app_update/notifier/app_update_notifier.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/home/widget/connection_button.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/features/profile/widget/profile_tile.dart';
import 'package:hiddify/features/proxy/active/active_proxy_card.dart';
import 'package:hiddify/features/proxy/active/active_proxy_delay_indicator.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/stats/notifier/stats_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/utils/number_formatters.dart';
import 'package:hiddify/utils/saqanet_links.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

Future<void> _pickLanguage(WidgetRef ref) async {
  final locale = ref.read(localePreferencesProvider);
  final selected = await ref
      .read(dialogNotifierProvider.notifier)
      .showSettingPicker<AppLocale>(
        title: 'Язык',
        selected: locale,
        onReset: () => ref.read(localePreferencesProvider.notifier).changeLocale(AppLocale.en),
        options: AppLocale.values,
        getTitle: (e) => e.localeName,
      );
  if (selected != null) {
    await ref.read(localePreferencesProvider.notifier).changeLocale(selected);
  }
}

enum _SettingsMenuAction { profiles, config, apps, language, notWorking, telegram, checkUpdate, about, tariffs }

class HomePage extends HookConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translationsProvider).requireValue;
    final hasAnyProfile = ref.watch(hasAnyProfileProvider).valueOrNull ?? false;
    final connected = ref.watch(connectionNotifierProvider).valueOrNull?.isConnected ?? false;
    final activeProxy = ref.watch(activeProxyNotifierProvider).valueOrNull;
    final stats = ref.watch(statsNotifierProvider).asData?.value ?? SystemInfo.create();
    final profilesAsync = ref.watch(profilesNotifierProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A12),
        title: Row(
          children: [
            ClipOval(child: Image.asset('assets/images/sn_logo.png', height: 28, width: 28, fit: BoxFit.cover)),
            const Gap(8),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: t.common.appTitle),
                  const TextSpan(text: " "),
                  const WidgetSpan(child: AppVersionLabel(), alignment: PlaceholderAlignment.middle),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Инфо о сервере',
            icon: Icon(Icons.info_outline_rounded, color: theme.colorScheme.onSurfaceVariant),
            onPressed: activeProxy == null
                ? null
                : () => ref.read(dialogNotifierProvider.notifier).showProxyInfo(outboundInfo: activeProxy),
          ),
          PopupMenuButton<_SettingsMenuAction>(
            tooltip: 'Настройки',
            icon: Icon(Icons.settings_outlined, color: theme.colorScheme.onSurfaceVariant),
            onSelected: (action) {
              switch (action) {
                case _SettingsMenuAction.profiles:
                  ref.read(bottomSheetsNotifierProvider.notifier).showProfilesOverview();
                case _SettingsMenuAction.config:
                  context.goNamed('settings');
                case _SettingsMenuAction.apps:
                  context.goNamed('perAppProxy');
                case _SettingsMenuAction.language:
                  _pickLanguage(ref);
                case _SettingsMenuAction.notWorking:
                  context.goNamed('notWorking');
                case _SettingsMenuAction.telegram:
                  openSaqanetBot();
                case _SettingsMenuAction.checkUpdate:
                  ref.read(appUpdateNotifierProvider.notifier).check();
                case _SettingsMenuAction.about:
                  context.pushNamed('about');
                case _SettingsMenuAction.tariffs:
                  context.goNamed('tariffs');
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: _SettingsMenuAction.profiles, child: Text('Профили')),
              PopupMenuItem(value: _SettingsMenuAction.config, child: Text('Конфигурация')),
              PopupMenuItem(value: _SettingsMenuAction.apps, child: Text('Приложения')),
              PopupMenuItem(value: _SettingsMenuAction.language, child: Text('Язык')),
              PopupMenuItem(value: _SettingsMenuAction.notWorking, child: Text('Не работает?')),
              PopupMenuItem(value: _SettingsMenuAction.telegram, child: Text('Telegram @SAQANet_bot')),
              PopupMenuItem(value: _SettingsMenuAction.checkUpdate, child: Text('Проверить обновление')),
              PopupMenuItem(value: _SettingsMenuAction.about, child: Text('О приложении')),
              PopupMenuItem(value: _SettingsMenuAction.tariffs, child: Text('Тарифы')),
            ],
          ),
          Semantics(
            key: const ValueKey("profile_add_button"),
            label: t.pages.profiles.add,
            child: IconButton(
              icon: Icon(Icons.add_rounded, color: theme.colorScheme.primary),
              onPressed: () => ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile(),
            ),
          ),
          const Gap(8),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: const AssetImage('assets/images/world_map.png'),
            fit: BoxFit.cover,
            opacity: 0.09,
            colorFilter: theme.brightness == Brightness.dark
                ? ColorFilter.mode(Colors.white.withValues(alpha: .15), BlendMode.srcIn)
                : ColorFilter.mode(Colors.grey.withValues(alpha: 1), BlendMode.srcATop),
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              children: [
                _StatusShield(connected: connected),
                const Gap(8),
                const Column(children: [ConnectionButton(), ActiveProxyDelayIndicator()]),
                const Gap(8),
                _TrafficCard(uplinkTotal: stats.uplinkTotal.toInt(), downlinkTotal: stats.downlinkTotal.toInt()),
                const ActiveProxyFooter(),
                const Gap(8),
                Expanded(
                  child: switch (profilesAsync) {
                    AsyncData(value: final profiles) when profiles.isNotEmpty => ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: profiles.length,
                      separatorBuilder: (_, _) => const Gap(10),
                      itemBuilder: (context, i) => ProfileTile(profile: profiles[i]),
                    ),
                    _ => Center(
                      child: Text(
                        hasAnyProfile ? '' : 'Нет серверов — добавьте подписку',
                        style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusShield extends StatelessWidget {
  const _StatusShield({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    final bg = connected ? const Color(0xFF0D2B1E) : const Color(0xFF1F1525);
    final fg = connected ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(9)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
            const Gap(9),
            Text(connected ? 'Активен' : 'Не активен', style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

class _TrafficCard extends StatelessWidget {
  const _TrafficCard({required this.uplinkTotal, required this.downlinkTotal});

  final int uplinkTotal;
  final int downlinkTotal;

  @override
  Widget build(BuildContext context) {
    final active = uplinkTotal > 0 || downlinkTotal > 0;
    final valueColor = active ? const Color(0xFF10B981) : const Color(0xFFE5E7EB);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
      decoration: BoxDecoration(
        color: const Color(0xFF111120),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1e1e35)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    const Text('↑ ПЕРЕДАНО', style: TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
                    const Gap(3),
                    Text(uplinkTotal.size(), style: TextStyle(color: valueColor, fontWeight: FontWeight.bold, fontSize: 15)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    const Text('↓ ПОЛУЧЕНО', style: TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
                    const Gap(3),
                    Text(downlinkTotal.size(), style: TextStyle(color: valueColor, fontWeight: FontWeight.bold, fontSize: 15)),
                  ],
                ),
              ),
            ],
          ),
          const Gap(6),
          const Text('ID: SN—', style: TextStyle(color: Color(0xFF374151), fontSize: 13)),
        ],
      ),
    );
  }
}

class AppVersionLabel extends HookConsumerWidget {
  const AppVersionLabel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);

    final version = ref.watch(appInfoProvider).requireValue.presentVersion;
    if (version.isBlank) return const SizedBox();

    return Semantics(
      label: t.common.version,
      button: false,
      child: Text(
        version,
        textDirection: TextDirection.ltr,
        style: theme.textTheme.bodySmall?.copyWith(color: Colors.white),
      ),
    );
  }
}
