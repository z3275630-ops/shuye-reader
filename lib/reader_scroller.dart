// Adapted from Readium Kotlin Toolkit R2WebView (BSD-3-Clause).
// Copyright (c) 2018. Readium Foundation. All rights reserved.
// Dart port, 2026-10-09: page snap duration and quintic interpolation only.
// Source: 1b1f6b308a7b6f968b2bf1e66c84912879466f75.
// Full notice: assets/licenses/Readium.txt.
import 'dart:math' as math;

import 'package:flutter/animation.dart';

/// Readium's Android pager interpolator: (t - 1)^5 + 1.
class ReaderPagerCurve extends Curve {
  const ReaderPagerCurve();
  @override
  double transformInternal(double t) {
    final x = t - 1;
    return x * x * x * x * x + 1;
  }
}

/// Port of R2WebView.smoothScrollTo / distanceInfluenceForSnapDuration.
/// Velocity and dimensions use the same units (logical pixels here).
Duration readerPagerDuration(double distance, double width, double velocity) {
  final ratio = math.min(1.0, distance.abs() / width);
  final influence = math.sin((ratio - .5) * .3 * math.pi / 2);
  final adjustedDistance = width / 2 + width / 2 * influence;
  final duration = velocity.abs() > 0
      ? 4 * (1000 * (adjustedDistance / velocity).abs()).round()
      : ((distance.abs() / width + 1) * 100).toInt();
  return Duration(milliseconds: math.min(duration, 600));
}
