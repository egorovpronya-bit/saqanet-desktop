import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/utils/saqanet_links.dart';
import 'package:hiddify/utils/uri_utils.dart';

/// Mirrors the Android app's SubscriptionActivity: 9 fixed plans, no backend pricing API.
const _plans = [
  ('Один', [('30 дней', '99 ₽', 'one_30'), ('90 дней', '277 ₽', 'one_90'), ('180 дней', '554 ₽', 'one_180')]),
  ('Пара', [('30 дней', '199 ₽', 'pair_30'), ('90 дней', '557 ₽', 'pair_90'), ('180 дней', '1 114 ₽', 'pair_180')]),
  (
    'Семейный',
    [('30 дней', '299 ₽', 'family_30'), ('90 дней', '837 ₽', 'family_90'), ('180 дней', '1 674 ₽', 'family_180')],
  ),
];

class TariffsPage extends StatelessWidget {
  const TariffsPage({super.key});

  static Future<void> _showChoice(BuildContext context, String planId, String label) {
    return showDialog<void>(
      context: context,
      builder: (context) => SimpleDialog(
        backgroundColor: const Color(0xFF111120),
        title: Text(label, style: const TextStyle(color: Color(0xFFE5E7EB))),
        children: [
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(context);
              openSaqanetBot();
            },
            child: const Text('💬 Оплатить через Telegram', style: TextStyle(color: Color(0xFFE5E7EB))),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(context);
              UriUtils.tryLaunch(Uri.parse('${Constants.tariffsBuyUrlBase}$planId'));
            },
            child: const Text('🌐 Оплатить на сайте', style: TextStyle(color: Color(0xFFE5E7EB))),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A12),
        title: const Text('Тарифы'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final (category, items) in _plans) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                category,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            for (final (days, price, planId) in items)
              Card(
                color: const Color(0xFF111120),
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: Color(0xFF1e1e35)),
                ),
                child: ListTile(
                  title: Text(days, style: const TextStyle(color: Color(0xFFE5E7EB))),
                  trailing: Text(
                    price,
                    style: const TextStyle(color: Color(0xFF4F6EF7), fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  onTap: () => _showChoice(context, planId, '$category · $days · $price'),
                ),
              ),
            const Gap(8),
          ],
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF4F6EF7),
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: () => _showChoice(context, 'one_90', 'Оплата подписки'),
            child: const Text('Оплатить'),
          ),
        ],
      ),
    );
  }
}
