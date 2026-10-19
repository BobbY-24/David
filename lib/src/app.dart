import 'package:flutter/material.dart';

import 'ui/desk_page.dart';
import 'ui/theme.dart';

class FieldlineApp extends StatelessWidget {
  const FieldlineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fieldline',
      debugShowCheckedModeBanner: false,
      theme: fieldlineTheme(),
      home: const DeskPage(),
    );
  }
}
