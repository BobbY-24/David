import 'package:flutter/material.dart';

import 'jobs/job_client.dart';
import 'ui/desk_page.dart';
import 'ui/theme.dart';

class FieldlineApp extends StatelessWidget {
  const FieldlineApp({super.key, this.jobClient});

  final JobClient? jobClient;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fieldline',
      debugShowCheckedModeBanner: false,
      theme: fieldlineTheme(),
      home: DeskPage(jobClient: jobClient),
    );
  }
}
