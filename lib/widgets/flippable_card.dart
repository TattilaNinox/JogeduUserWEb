import 'package:flutter/material.dart';
import 'dart:math' as math;

class FlippableCard extends StatefulWidget {
  final String frontText;
  final String backText;
  final Axis flipAxis; // Axis.horizontal (Y) or Axis.vertical (X)
  final bool interactive;
  const FlippableCard(
      {super.key,
      required this.frontText,
      required this.backText,
      this.flipAxis = Axis.horizontal,
      this.interactive = true});

  @override
  State<FlippableCard> createState() => _FlippableCardState();
}

class _FlippableCardState extends State<FlippableCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  bool _isFront = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _animation = Tween<double>(begin: 0, end: 1).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleCard() {
    if (_controller.isCompleted || _controller.velocity > 0) {
      _controller.reverse();
    } else {
      _controller.forward();
    }
    setState(() => _isFront = !_isFront);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.interactive) {
      // csak statikus előlap
      return _buildCardSide(widget.frontText, true);
    }
    return GestureDetector(
      onTap: _toggleCard,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          final angle = _animation.value * math.pi;
          final transform = Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(widget.flipAxis == Axis.horizontal ? angle : 0)
            ..rotateX(widget.flipAxis == Axis.vertical ? angle : 0);

          return Transform(
            transform: transform,
            alignment: Alignment.center,
            child: _animation.value <= 0.5
                ? _buildCardSide(widget.frontText, true)
                : Transform(
                    transform: Matrix4.identity()
                      ..rotateY(
                          widget.flipAxis == Axis.horizontal ? math.pi : 0)
                      ..rotateX(widget.flipAxis == Axis.vertical ? math.pi : 0),
                    alignment: Alignment.center,
                    child: _buildCardSide(widget.backText, false),
                  ),
          );
        },
      ),
    );
  }

  Widget _buildCardSide(String text, bool isFront) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isFront ? Colors.white : const Color(0xFFF5F5F5),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 12.0 : 28.0),
          child: isFront
              ? Text(
                  text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: isMobile ? 13 : 18,
                    fontFamily: 'Inter', // Jegyzet betűtípusa
                    fontWeight: FontWeight.bold,
                  ),
                )
              : Text(
                  text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: const Color(0xFF2D3748), // Jegyzet tartalom színe
                    fontSize: isMobile ? 11 : 16,
                    fontFamily: 'Inter', // Jegyzet betűtípusa
                    fontWeight: FontWeight.w500,
                    height: 1.5, // Jegyzet sormagasság
                  ),
                ),
        ),
      ),
    );
  }
}
