import 'dart:async';
import 'dart:io';

import 'package:shelf/shelf_io.dart' as io;
import 'package:suceava_alerts_backend/suceava_alerts_backend.dart';

Future<void> main() async {
  final BackendConfig config;
  try {
    config = BackendConfig.fromEnvironment(Platform.environment);
  } on ArgumentError catch (e) {
    stderr.writeln('Configuration error: ${e.message}');
    exitCode = 64;
    return;
  }

  final fetcher = PoliteFetcher(
    userAgent: config.userAgent,
    // The train files are about 12 MB each and a free host's route to the
    // source can be slow.
    timeout: const Duration(seconds: 60),
  );
  final pipeline = TransportPipeline(
    adapters: config.buildAdapters(),
    fetcher: fetcher,
    now: () => DateTime.now().toUtc(),
  );

  final handler = buildHandler(pipeline, now: () => DateTime.now().toUtc());

  final server = await io.serve(
    config.corsAllowOrigin == null
        ? handler
        : withCors(handler, config.corsAllowOrigin!),
    config.host,
    config.port,
  );
  stdout.writeln('Listening on ${server.address.address}:${server.port}  '
      '(GET /v1/arrivals, /v1/sources, /healthz)');

  // Load the sources right away instead of on the first request, so a cold
  // start (Render Free wakes the service on demand) is already loading while
  // the first client waits. /healthz does not wait for this.
  unawaited(pipeline.ensureFresh());
}
