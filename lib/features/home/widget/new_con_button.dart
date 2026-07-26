import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/widget/animated_text.dart';
import 'package:hiddify/gen/assets.gen.dart';

class CircleDesignWidget extends StatelessWidget {
  final double animationValue;
  final Color color;
  final VoidCallback onTap;
  final bool enabled;
  final String label;

  const CircleDesignWidget({
    Key? key,
    required this.animationValue,
    required this.color,
    required this.onTap,
    required this.enabled,
    required this.label,
  }) : super(key: key);
  // GestureDetector(
  //       onTap: onTap,
  //       child: CustomPaint(
  //         size: const Size(168, 168),
  //         painter: CirclePainter(
  //           animationValue: animationValue,
  //           baseColor: color,
  //         ),
  //       )
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // CircleDesignWidget(newButtonColor: newButtonColor, onTap: onTap, animated: animated),
        Semantics(
          button: true,
          enabled: enabled,
          label: label,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              // boxShadow: [
              //   BoxShadow(
              //     blurRadius: 16,
              //     color: color.withOpacity(0.5),
              //   ),
              // ],
            ),
            width: 168,
            height: 168,
            child: Material(
              key: const ValueKey("home_connection_button"),
              shape: const CircleBorder(),
              // color: Colors.white,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(0),
                  child: TweenAnimationBuilder(
                    tween: ColorTween(end: color),
                    duration: const Duration(milliseconds: 250),
                    builder: (context, value, child) {
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox.expand(
                            child: CustomPaint(
                              painter: CirclePainter(animationValue: animationValue, baseColor: value!),
                            ),
                          ),
                          Assets.images.logo.svg(
                            width: 56,
                            height: 56,
                            colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ).animate(target: enabled ? 0 : 1).blurXY(end: 1),
          ).animate(target: enabled ? 0 : 1).scaleXY(end: .88, curve: Curves.easeIn),
        ),
        const Gap(16),
        ExcludeSemantics(child: AnimatedText(label, style: Theme.of(context).textTheme.titleMedium)),
      ],
    );
  }
}

class CirclePainter extends CustomPainter {
  final double animationValue;
  final Color baseColor;

  CirclePainter({required this.animationValue, required this.baseColor});

  @override
  void paint(Canvas canvas, Size size) {
    final double cx = size.width / 2;
    final double cy = size.height / 2;

    final innerCircleColor = [baseColor.withAlpha(230), baseColor];

    // Outer circle (pulsing animation for connecting state)
    final Paint outerCirclePaint = Paint()
      ..color = baseColor.withOpacity(0.15)
      ..style = PaintingStyle.fill;
    final double outerRadius = 84 * animationValue;

    canvas.drawCircle(Offset(cx, cy), outerRadius, outerCirclePaint);

    // Middle circle
    final Paint middleCirclePaint = Paint()
      ..color = baseColor.withOpacity(.3)
      ..style = PaintingStyle.fill;
    final double middleRadius = 60 * animationValue + (1 - animationValue) / 3;
    canvas.drawCircle(Offset(cx, cy), middleRadius, middleCirclePaint);

    // Inner circle with gradient
    final Paint innerCirclePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: innerCircleColor,
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: 36));
    final double innerRadius = 36;
    canvas.drawCircle(Offset(cx, cy), innerRadius, innerCirclePaint);

  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
