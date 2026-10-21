import 'package:flutter/material.dart';

import 'jobs/engagement_service.dart';
import 'jobs/job_client.dart';
import 'jobs/model_service.dart';
import 'jobs/spec_service.dart';
import 'ui/desk_page.dart';
import 'ui/theme.dart';

class DavidApp extends StatelessWidget {
  const DavidApp({
    super.key,
    this.jobClient,
    this.modelService,
    this.specService,
    this.engagementService,
  });

  final JobClient? jobClient;
  final ModelService? modelService;
  final SpecService? specService;
  final EngagementService? engagementService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'David',
      debugShowCheckedModeBanner: false,
      theme: davidTheme(),
      home: DeskPage(
        jobClient: jobClient,
        modelService: modelService,
        specService: specService,
        engagementService: engagementService,
      ),
    );
  }
}
