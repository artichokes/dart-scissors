library scissors.src.css_mirroring.bidi_css_generator.ruleset_processors;

import 'package:csslib/visitor.dart' show Declaration, RuleSet;
import 'package:quiver/check.dart';

import 'buffered_transaction.dart';
import 'edit_configuration.dart';
import 'mirrored_entities.dart';
import '../utils/enum_parser.dart';

enum RemovalResult { removedSome, removedAll }

/// Returns true if the [RuleSet] was completely removed, false otherwise.
RemovalResult editRuleSet(MirroredEntity<RuleSet> mirroredRuleSet,
    EditConfiguration editConfig, BufferedTransaction trans) {
  final subTransaction = trans.createSubTransaction();

  MirroredEntities<Declaration> mirroredDeclarations = mirroredRuleSet
      .getChildren((RuleSet r) => r.declarationGroup.declarations);

  /// Iterate over Declarations in RuleSet and store start and end points of
  /// declarations to be removed.
  var removedCount = 0;
  mirroredDeclarations.forEach((MirroredEntity<Declaration> decl) {
    checkState(decl.original.value is Declaration,
        message: () => 'Expected a declaration, got $decl');

    bool isEqual =
        decl.original.value.span.text == decl.flipped.value.span.text;

    var shouldRemoveDecl =
        editConfig.mode == RetentionMode.keepBidiNeutral ? !isEqual : isEqual;

    if (shouldRemoveDecl) {
      decl.remove(editConfig.mode, trans);
      removedCount++;
    }
  });

  var ruleSet = mirroredRuleSet.choose(editConfig.mode);
  if (removedCount == mirroredDeclarations.length) {
    ruleSet.remove(trans);
    return RemovalResult.removedAll;
  } else {
    /// Add direction attribute to RuleId for direction-specific RuleSet.
    if (editConfig.mode != RetentionMode.keepBidiNeutral) {
      var dir = enumName(editConfig.targetDirection);
      ruleSet.prepend(trans, ':host-context([dir="$dir"]) ');
    }
    subTransaction.commit();
    return RemovalResult.removedSome;
  }
}
