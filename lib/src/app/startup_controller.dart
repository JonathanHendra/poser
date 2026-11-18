import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final startupProvider = ChangeNotifierProvider<StartupController>(
  (ref) => StartupController(),
);

class StartupController extends ChangeNotifier {
  StartupController() {
    _timer = Timer(const Duration(milliseconds: 1400), () {
      ready = true;
      notifyListeners();
    });
  }
  late final Timer _timer;
  bool ready = false;
  bool introCompleted = false;
  void completeIntro() {
    introCompleted = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }
}
