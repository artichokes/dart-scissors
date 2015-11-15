// Copyright 2015 Google Inc. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
part of scissors.src.permutations.transformer;

abstract class PermutationsSettings {
  final expectedPartCounts =
      new Setting<Map>('expectedPartCounts', defaultValue: {});

  final potentialLocales = new Setting<List<String>>(
      'potentialLocales',
      defaultValue: numberFormatSymbols.keys.toList());

  final ltrImport = new Setting<String>('ltrImport');
  final rtlImport = new Setting<String>('rtlImport');

  final generatePermutations = makeBoolSetting('generatePermutations');

  final reoptimizePermutations =
      makeOptimSetting('reoptimizePermutations', false);

  final javaPath = makePathSetting('javaPath', pathResolver.defaultJavaPath);

  final closureCompilerJarPath = makePathSetting(
      'closureCompilerJar', pathResolver.defaultClosureCompilerJarPath);
}

class _PermutationsSettings extends SettingsBase with PermutationsSettings {
  _PermutationsSettings(settings) : super(settings);
}