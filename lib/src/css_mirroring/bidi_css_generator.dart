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
library scissors.src.css_mirroring.bidi_css_generator;

import 'dart:async';

import 'package:csslib/parser.dart' show parse;
import 'package:csslib/visitor.dart'
    show
        CharsetDirective,
        Declaration,
        Directive,
        FontFaceDirective,
        HostDirective,
        ImportDirective,
        MediaDirective,
        NamespaceDirective,
        PageDirective,
        RuleSet,
        StyleSheet,
        TreeNode;

import 'package:source_maps/refactor.dart';
import 'package:source_span/source_span.dart';

import 'buffered_transaction.dart';
import 'directive_processors.dart';
import 'edit_configuration.dart';
import 'mirrored_entities.dart';
import 'rulesets_processor.dart';
import 'css_utils.dart' show isDirectionInsensitive, hasNestedRuleSets;

/// Type of a function that does LTR/RTL mirroring of a css.
typedef Future<String> CssFlipper(String inputCss);

/// BidiCssGenerator generates a CSS which comprises of orientation neutral,
/// orientation specific and flipped orientation specific parts.
///
/// See BidirectionalCss.md for more details.
class BidiCssGenerator {
  final String _originalCss;
  final String _flippedCss;
  final String _sourceId;
  final Direction _nativeDirection;

  MirroredEntities<TreeNode> _topLevels;

  BidiCssGenerator._(this._originalCss, this._flippedCss, this._sourceId,
      this._nativeDirection) {
    _topLevels = new MirroredEntities(
        _originalCss,
        parse(_originalCss).topLevels,
        _flippedCss,
        parse(_flippedCss).topLevels);
  }

  static build(String originalCss, String cssSourceId,
      Direction nativeDirection, CssFlipper cssFlipper) async {
    return new BidiCssGenerator._(originalCss, await cssFlipper(originalCss),
        cssSourceId, nativeDirection);
  }

  TextEditTransaction _makeTransaction(String css) =>
      new TextEditTransaction(css, new SourceFile(css, url: _sourceId));

  /// Main function which returns the bidirectional CSS.
  String getOutputCss() {
    var orientationNeutralTransaction = _makeTransaction(_originalCss);
    var orientationSpecificTransaction = _makeTransaction(_originalCss);
    var flippedOrientationSpecificTransaction = _makeTransaction(_flippedCss);

    final orientationNeutral =
        new EditConfiguration(RetentionMode.keepBidiNeutral, _nativeDirection);
    final orientationSpecific = new EditConfiguration(
        RetentionMode.keepOriginalBidiSpecific, _nativeDirection);
    final flippedOrientationSpecific = new EditConfiguration(
        RetentionMode.keepFlippedBidiSpecific, flipDirection(_nativeDirection));

    /// Modifies the transactions to contain only the desired parts.
    _editCss(orientationNeutralTransaction, orientationNeutral);
    _editCss(orientationSpecificTransaction, orientationSpecific);
    _editCss(flippedOrientationSpecificTransaction, flippedOrientationSpecific);

    String getText(TextEditTransaction t) => (t.commit()..build('')).text;

    return [
      getText(orientationNeutralTransaction),
      getText(orientationSpecificTransaction),
      getText(flippedOrientationSpecificTransaction)
    ].where((t) => t.trim().isNotEmpty).join('\n');
  }

  /// Takes transaction to edit, the retention mode which defines which part to
  /// retain and the direction of the output CSS.
  ///
  /// In case of rulesets it drops declarations in them and if all the declaration
  /// in it have to be removed, it removes the rule itself.
  ///
  /// In case of Directives, it edits rulesets in them and if all the rulesets have
  /// to be removed, it removes Directive Itself
  void _editCss(
      TextEditTransaction textEditTrans, EditConfiguration editConfig) {
    var trans = new BufferedTransaction(textEditTrans);
    _topLevels.forEach((MirroredEntity<TreeNode> entity) {
      var original = entity.original.value;
      if (original is RuleSet) {
        editRuleSet(entity, editConfig, trans);
      } else if (hasNestedRuleSets(original)) {
        editDirectiveWithNestedRuleSets(
            entity, entity.getChildren((d) => d.rulesets), editConfig, trans);
      } else if (isDirectionInsensitive(original)) {
        if (editConfig.mode != RetentionMode.keepBidiNeutral) {
          entity.remove(editConfig.mode, trans);
        }
      } else {
        throw new StateError('Node type not handled: ${original.runtimeType}');
      }
    });
    trans.commit();
  }
}
