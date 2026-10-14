import 'dart:async';

import 'package:flutter/widgets.dart';

/// Rebuilds [builder] once a second — for a clock that must tick even when
/// nothing else on screen changes (e.g. the battery test's TEST time: the
/// simulated ride runs at a constant speed, so the ride metrics never change
/// and the surrounding screen never rebuilds on its own).
class EverySecond extends StatefulWidget {
  const EverySecond({super.key, required this.builder});

  final WidgetBuilder builder;

  @override
  State<EverySecond> createState() => _EverySecondState();
}

class _EverySecondState extends State<EverySecond> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
