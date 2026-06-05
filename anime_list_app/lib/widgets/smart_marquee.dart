import 'package:flutter/material.dart';
import 'package:marquee/marquee.dart';

class SmartMarquee extends StatelessWidget {
  final String text;
  final TextStyle style;
  final double height;
  final double blankSpace;
  final double velocity;
  final Duration pauseAfterRound;
  final TextAlign textAlign;

  const SmartMarquee({
    super.key,
    required this.text,
    required this.style,
    this.height = 30,
    this.blankSpace = 60.0,
    this.velocity = 30.0,
    this.pauseAfterRound = const Duration(seconds: 3),
    this.textAlign = TextAlign.start,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textPainter = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: double.infinity);

        final bool overflows = textPainter.width > constraints.maxWidth;

        if (overflows) {
          return SizedBox(
            height: height,
            child: Marquee(
              text: "$text       ",
              style: style,
              scrollAxis: Axis.horizontal,
              blankSpace: blankSpace,
              velocity: velocity,
              pauseAfterRound: pauseAfterRound,
            ),
          );
        } else {
          return Text(
            text,
            style: style,
            textAlign: textAlign,
            maxLines: 1,
            overflow: TextOverflow.visible,
          );
        }
      },
    );
  }
}
