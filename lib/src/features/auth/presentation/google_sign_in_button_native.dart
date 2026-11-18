import 'package:flutter/material.dart';

Widget googleSignInButton(VoidCallback onPressed) => FilledButton.icon(
  onPressed: onPressed,
  icon: const Icon(Icons.login),
  label: const Text('Mulai dengan Google'),
);
