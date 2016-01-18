library scissors.src.css_mirroring.cssjanus_runner;

import 'dart:async';
import 'dart:io';

import '../utils/process_utils.dart';

/// Runs cssjanus (https://github.com/cegov/wiki/tree/master/maintenance/cssjanus)
/// on [css], and returns the flipped CSS.
///
/// [cssJanusPath] points to an executable.
Future<String> runCssJanus(String css, String cssJanusPath) async =>
    successString('Closure Compiler',
        await pipeInAndOutOfNewProcess(
            await Process.start(cssJanusPath, []), css));
