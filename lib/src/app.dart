import 'package:flutter/material.dart';

import 'jobs/job_client.dart';
import 'ui/desk_page.dart';
import 'ui/theme.dart';

class DavidApp extends StatelessWidget {
  const DavidApp({super.key, this.jobClient});

  final JobClient? jobClient;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'David',
      debugShowCheckedModeBanner: false,
      theme: davidTheme(),
      home: DeskPage(jobClient: jobClient),
    );
  }
}
