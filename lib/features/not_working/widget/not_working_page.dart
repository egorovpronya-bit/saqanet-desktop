import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/utils/saqanet_links.dart';

/// Mirrors the Android app's NotWorkingActivity: static 5-step troubleshooting list.
const _steps = [
  'Отключите другие VPN-приложения',
  'Проверьте подписку в @SAQANet_bot — возможно истёк срок',
  'Попробуйте сменить протокол: VLESS → Trojan',
  'Получите новый ключ в боте. При обращении укажите ваш ID',
  'Включите Kill Switch в настройках для защиты при обрыве',
];

class NotWorkingPage extends StatelessWidget {
  const NotWorkingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A12),
        title: const Text('Что делать если VPN не работает?'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.warning_rounded, color: Color(0xFFEF4444), size: 48),
          const Gap(20),
          for (var i = 0; i < _steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF4F6EF7)),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                  const Gap(12),
                  Expanded(
                    child: Text(_steps[i], style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14, height: 1.4)),
                  ),
                ],
              ),
            ),
          const Gap(8),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF4F6EF7),
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: openSaqanetBot,
            child: const Text('ПЕРЕЙТИ В @SAQANet_bot'),
          ),
        ],
      ),
    );
  }
}
