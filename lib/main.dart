import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/jobs/engagement_service.dart';

void main() {
  runApp(DavidApp(engagementService: HttpEngagementService()));
}
