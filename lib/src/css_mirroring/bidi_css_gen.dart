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
library scissors.src.css_mirroring.bidi_css_gen;

import 'dart:async';

import 'package:csslib/parser.dart' show parse;
import 'package:csslib/visitor.dart'
    show RuleSet, StyleSheet, TreeNode, Declaration, Directive, MediaDirective, HostDirective, PageDirective, CharsetDirective, FontFaceDirective, ImportDirective, NamespaceDirective;
import 'package:quiver/check.dart';
import 'package:source_maps/refactor.dart';
import 'package:source_span/source_span.dart';

import '../utils/enum_parser.dart';
import 'transformer.dart' show CssMirroringSettings, Direction, flipDirection;

enum RetentionMode {
  keepBidiNeutral,  /// to keep parts of css which is direction independent eg: color and width
  keepOriginalBidiSpecific, /// to keep direction dependent parts of original css eg: margin.
  keepFlippedBidiSpecific /// to keep direction dependent parts of flipped css.
}

/// GenerateBidiCss generates a Css which comprises of Orientation Neutral, Orientation Specific and Flipped Orientation Specific parts.
/// Eg: foo {
///           color: red;
///           margin-left: 10px;
///         }
/// gets converted to
///     foo {
///           color: red;                       /// Orientation Neutral (Independent of direction)
///         }
///
///    :host-context([dir="ltr"]) foo {
///           margin-left: 10px;                /// Orientation Specific (Orientation specific parts in original css)
///         }
///
///    :host-context([dir="rtl"]) foo {
///           margin-right: 10px;               /// Flipped Orientation Specific (Orientation specific parts in flipped css)
///        }
///
/// Its takes a css string, sourcefile name, nativeDirection of input css and path to cssjanus.
/// It generates a flipped version of the input css by passing it to cssJanus.
/// Eg: passing foo {
///           color: red;
///           margin-left: 10px;          /// will be used as Original css
///         }
/// to css janus returns
///     foo {
///           color: red;
///           margin-right: 10px;         /// will be used as flipped css.
///         }
///
/// Next we create three transactions(css strings)
///     1) Orientation Neutral: It is made from original css string. Direction dependent parts will be removed from it to keep only neutral parts.
///               eg: Initially contains foo { color: red; margin-left: 10px;} and will get modified to foo { color: red;}
///     2) Orientation specific: It is made from original css string.
///                              Direction independent parts will be removed from it to keep only direction dependent parts of original css.
///               eg: Initially contains foo { color: red; margin-left: 10px;} and will get modified to :host-context([dir="ltr"]) foo { margin-left: 10px;}
///     3) Flipped Orientation specific: It is made from flipped css string.
///                              Direction independent parts will be removed from it to keep only direction dependent parts of original css.
///               eg: Initially contains foo { color: red; margin-right: 10px;} and will get modified to :host-context([dir="rtl"]) foo { margin-right: 10px;}
///
/// So for each of these transactions we extract toplevels of the originalCss and flippedCss. It iterates over these topLevels.
/// If it is of type rule set
///     Iterates over declarations in them.
///     Depending on the mode of execution which could be [keepBidiNeutral], [keepOriginalBidiSpecific], [keepFlippedBidiSpecific],
///     check if the declaration is to be removed and store their start and end points.
///     Now if only some declarations have to be removed, remove them using their start and end points already stored.
///     And if all declarations in a ruleset are to be removed, Remove the ruleset (No need to keep empty rule)
///
/// If it is of type Media or Host Directive
///   eg:
///    @media screen and (min-width: 401px) {
///                  foo { margin-left: 13px }             /// Media Directive containing ruleset foo
///                  }
///   Directive --> RuleSets --> Declarations
///   Pick a ruleset:
///     stores removable declarations in it ->
///     If only some of the declaration have to be removed -> remove them from transaction.
///     If all declarations in ruleset removable -> store start and end of rule set(dont edit transaction because if all rulesets of directive have to be deleted then we will delete directive itself)
///   If only some rulesets in Directive have to be removed -> remove them using store start and end points
///   If all the rulesets have to be removed -> remove the Directive itself.
///
/// If it is a Direction Independent Directive
///   eg:
///     @charset "UTF-8";                                 /// Charset Directive
///     @namespace url(http://www.w3.org/1999/xhtml);     /// Namespace Directive
///  Keep it in one of the transaction and remove it from other two (Here we are keeping it in Orientation Neutral transaction).
///
/// We then combine these transactions to get the expected output css.

typedef Future<String> CssFlipper(String src);

class _PendingRemovals {
  final String source;
  final TextEditTransaction _transaction;
  // List to contain start and end location of pending removals.
  var _startLocations = <int>[];
  var _endLocations = <int>[];

  _PendingRemovals(TextEditTransaction trans)
      : _transaction = trans,
        source = trans.file.getText(0);

  void addRemoval(int start, int end) {
    _startLocations.add(start);
    _endLocations.add(end);
  }

  void commitRemovals() {
    for (int iDecl = 0; iDecl < _startLocations.length; iDecl++) {
      _transaction.edit(_startLocations[iDecl], _endLocations[iDecl], '');
    }
    _startLocations.clear();
    _endLocations.clear();
  }
}

class BidiCssGenerator {
  final String _originalCss;
  final String _flippedCss;
  final String _cssSourceId;
  final List<TreeNode> _originalTopLevels;
  final List<TreeNode> _flippedTopLevels;
  final Direction _nativeDirection;

  BidiCssGenerator._(String originalCss, String flippedCss, this._cssSourceId, this._nativeDirection)
      : _originalCss = originalCss,
        _flippedCss = flippedCss,
        _originalTopLevels = parse(originalCss).topLevels,
        _flippedTopLevels = parse(flippedCss).topLevels;

  static build(
      String originalCss, String cssSourceId, Direction nativeDirection, CssFlipper cssFlipper) async {
    return new BidiCssGenerator._(originalCss, await cssFlipper(originalCss), cssSourceId, nativeDirection);
  }


  /// main function which returns the bidirectional css.
  String getOutputCss() {
    var orientationNeutral = _makeTransaction(_originalCss, _cssSourceId);
    var orientationSpecific = _makeTransaction(_originalCss, _cssSourceId);
    var flippedOrientationSpecific = _makeTransaction(_flippedCss, _cssSourceId);
    /// Modifies the transactions to contain only the desired parts.

    _editTransaction(orientationNeutral, RetentionMode.keepBidiNeutral, _nativeDirection);
    _editTransaction(orientationSpecific, RetentionMode.keepOriginalBidiSpecific, _nativeDirection);
    _editTransaction(flippedOrientationSpecific, RetentionMode.keepFlippedBidiSpecific, flipDirection(_nativeDirection));

    String getText(TextEditTransaction t) => (t.commit()..build('')).text;

    return [
      getText(orientationNeutral),
      getText(orientationSpecific),
      getText(flippedOrientationSpecific)
    ].join('\n');
  }

  /// Makes transaction from input string.
  static TextEditTransaction _makeTransaction(String inputCss, String url) =>
      new TextEditTransaction(inputCss, new SourceFile(inputCss, url: url));

  /// Takes transaction to edit, the retention mode which defines which part to retain and the direction of the output css.
  /// In case rulesets it drops declarations in them and if all the declaration in it have to be removed, it removes the rule itself.
  /// In case Directives, it edits rulesets in them and if all the rulesets have to be removed, it removes Directive Itself
  _editTransaction(TextEditTransaction trans, RetentionMode mode, Direction targetDirection) {

    /// Iterate over topLevels.
    for (int iTopLevel = 0; iTopLevel < _originalTopLevels.length; iTopLevel++) {
      var originalTopLevel = _originalTopLevels[iTopLevel];
      var flippedTopLevel = _flippedTopLevels[iTopLevel];

      if (originalTopLevel is RuleSet && flippedTopLevel is RuleSet) {
        _editRuleSet(trans, mode, targetDirection, iTopLevel);
      }
      else if(originalTopLevel.runtimeType == flippedTopLevel.runtimeType && (originalTopLevel is MediaDirective || originalTopLevel is HostDirective)) {
        _editDirectives(trans, originalTopLevel, flippedTopLevel, mode, targetDirection);
      }
      else if(originalTopLevel.runtimeType == flippedTopLevel.runtimeType && _isDirectionIndependent(originalTopLevel)) {
        if (mode != RetentionMode.keepBidiNeutral) {
          _removeRuleSet(trans,  mode == RetentionMode.keepFlippedBidiSpecific ? _flippedTopLevels : _originalTopLevels, iTopLevel);
        }
      }
      else {
        checkState(originalTopLevel.runtimeType == flippedTopLevel.runtimeType);
      }
    }
  }

  /// Edit the topLevel Ruleset.
  /// It takes transaction, the topLevels of original and flipped css, Retantion mode, Direction of output css, the index of current topLevel and end of parent of topLevel.
   _editRuleSet(TextEditTransaction trans, RetentionMode mode, Direction targetDirection, int iTopLevel) {
     var removals = new _PendingRemovals(trans);
     var usedTopLevels = mode == RetentionMode.keepFlippedBidiSpecific ? _flippedTopLevels : _originalTopLevels;
    _storeRemovableDeclarations(removals, _originalTopLevels, _flippedTopLevels, mode, iTopLevel);
    if (_isRuleRemovable(removals, _originalTopLevels[iTopLevel])) {
      _removeRuleSet(trans, usedTopLevels, iTopLevel);
    }
    else {
      removals.commitRemovals();
      /// Add direction attribute to RuleId for direction-specific RuleSet.
      if (mode != RetentionMode.keepBidiNeutral) {
        _prependDirectionToRuleSet(trans, usedTopLevels[iTopLevel], targetDirection);
      }
    }
  }

  _editDirectives(TextEditTransaction trans, var originalDirective, var flippedDirective, RetentionMode mode, Direction targetDirection) {
    var originalRuleSets = originalDirective.rulesets;
    var flippedRuleSets = flippedDirective.rulesets;
    var usedDirective = mode == RetentionMode.keepFlippedBidiSpecific ? flippedDirective : originalDirective;
    _PendingRemovals removableRuleSets = new _PendingRemovals(trans);
    for(int iRuleSet = 0; iRuleSet < originalRuleSets.length; iRuleSet++) {
        _PendingRemovals removableDeclarations = new _PendingRemovals(trans);
        _storeRemovableDeclarations(removableDeclarations, originalRuleSets, flippedRuleSets, mode, iRuleSet);
        if(_isRuleRemovable(removableDeclarations, originalRuleSets[iRuleSet])) {
          removableRuleSets.addRemoval(_getNodeStart(originalRuleSets[iRuleSet]), _getRuleSetEnd(usedDirective.rulesets, iRuleSet, usedDirective.span.end.offset));
        }
      else {
          removableDeclarations.commitRemovals();
          if (mode != RetentionMode.keepBidiNeutral) {
            _prependDirectionToRuleSet(trans, usedDirective.rulesets[iRuleSet], targetDirection);
          }
        }
    }
    if(removableRuleSets._startLocations.length == originalRuleSets.length ) { // All rules are to be deleted
      _removeDirective(trans, usedDirective);
    }
    else {
      removableRuleSets.commitRemovals();
    }
  }

  /// Stores start and end locations of removable declarations in a ruleset based upon the retension mode.
  _storeRemovableDeclarations(_PendingRemovals removals, List<RuleSet> originalTopLevels, List<RuleSet> flippedTopLevels, RetentionMode mode, int iTopLevel) {
    var originalDecls = originalTopLevels[iTopLevel].declarationGroup.declarations;
    var flippedDecls = flippedTopLevels[iTopLevel].declarationGroup.declarations;

    /// Iterate over Declarations in RuleSet and store start and end points of declarations to be removed.
    for (int iDecl = 0; iDecl < originalDecls.length; iDecl++) {
      if (originalDecls[iDecl] is Declaration && flippedDecls[iDecl] is Declaration) {
        if (_shouldRemoveDecl(mode, originalDecls[iDecl], flippedDecls[iDecl])) {
          var decls = mode == RetentionMode.keepFlippedBidiSpecific ? flippedDecls : originalDecls;
          removals.addRemoval(decls[iDecl].span.start.offset, _getDeclarationEnd(removals.source, iDecl, decls));
        }
      }
      else {
        checkState(originalTopLevels[iTopLevel].runtimeType == flippedTopLevels[iTopLevel].runtimeType);
      }
    }
  }

  _prependDirectionToRuleSet(TextEditTransaction trans, RuleSet ruleSet, Direction targetDirection) {
    trans.edit(ruleSet.span.start.offset, ruleSet.span.start.offset,
        ':host-context([dir="${enumName(targetDirection)}"]) ');
  }

  /// Removes a rule from the transaction.
  _removeRuleSet(TextEditTransaction trans, List<RuleSet> rulesets, int iTopLevel) {
    trans.edit(_getNodeStart(rulesets[iTopLevel]), _getRuleSetEnd(rulesets, iTopLevel, trans.file.length), '');
  }

  _removeDirective(TextEditTransaction trans, TreeNode topLevel) {
    trans.edit(_getNodeStart(topLevel) , topLevel.span.end.offset, '');
  }

  static int _getNodeStart(TreeNode node) {
    if(node is RuleSet)
      return node.span.start.offset;
    // In case of Directives since the node span start does not include '@' so additional -1 is required.
    return node.span.start.offset - 1;
  }

  static int _getRuleSetEnd(List<RuleSet> ruleSets, int iTopLevel, int parentEnd) {
    var end = iTopLevel < ruleSets.length - 1
        ? _getNodeStart(ruleSets[iTopLevel + 1])
        : parentEnd;
    return end;
  }

  static int _getDeclarationEnd(String source, int iDecl, List<Declaration> decls) {
    if (iDecl < decls.length - 1) {
      return decls[iDecl + 1].span.start.offset;
    } else {
      int fileLength = source.length;
      int fromIndex = decls[iDecl].span.end.offset;
      try {
        while (fromIndex + 1 < fileLength) {
          if (source.substring(fromIndex, fromIndex + 2) == '/*') {
            while (source.substring(fromIndex, fromIndex + 2) != '*/') {
              fromIndex++;
            }
          }
          else if (source[fromIndex + 1] == '}')
            return fromIndex + 1;
          fromIndex++;
        }
      }
      catch (exception, stackTrace) {
        print('Invalid Css');
      }
    }
  }

  /// A rule can removed if all the declarations in the rule can be removed.
  bool _isRuleRemovable(_PendingRemovals removals, RuleSet rule) =>
      removals._startLocations.length == rule.declarationGroup.declarations.length;

  /// Checks if the declaration has to be removed based on the the Retention mode.
  static bool _shouldRemoveDecl(RetentionMode mode, Declaration original, Declaration flipped) {
    var isEqual = _areDeclarationsEqual(original, flipped);
    return mode == RetentionMode.keepBidiNeutral ? !isEqual : isEqual;
  }

}
/// Checks if a topLevel tree node is direction independent.
bool _isDirectionIndependent(TreeNode node) {
return node is CharsetDirective || node is FontFaceDirective || node is ImportDirective || node is NamespaceDirective;
}

bool _areDeclarationsEqual(Declaration a, Declaration b) =>
    a.span.text == b.span.text;