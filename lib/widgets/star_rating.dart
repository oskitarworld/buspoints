import 'package:flutter/material.dart';

class StarRating extends StatelessWidget {
  final int rating;
  final ValueChanged<int> onRatingChanged;
  final int starCount;
  final double size;

  const StarRating({
    super.key,
    required this.rating,
    required this.onRatingChanged,
    this.starCount = 5,
    this.size = 32,
  });

  Widget buildStar(int index) {
    return GestureDetector(
      onTap: () => onRatingChanged(index + 1),
      child: Icon(
        index < rating ? Icons.star : Icons.star_border,
        color: Colors.amber,
        size: size,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(starCount, buildStar),
    );
  }
}
