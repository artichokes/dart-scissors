library scissors.src.css_mirroring.directive_processors;

import 'package:csslib/visitor.dart' show Directive, RuleSet;

import 'buffered_transaction.dart';
import 'edit_configuration.dart';
import 'mirrored_entities.dart';
import 'rulesets_processor.dart' show editRuleSet, RemovalResult;

/// All removable declarations of ruleset are removed and if all declarations
/// in rulesets have to be removed, it removes ruleset itself.
/// Also if all rulesets have to be removed, it removes the directive.
editDirectiveWithNestedRuleSets(
    MirroredEntity<Directive> directive,
    MirroredEntities<RuleSet> nestedRuleSets,
    EditConfiguration editConfig,
    BufferedTransaction trans) {
  var subTransaction = trans.createSubTransaction();
  bool removedAll = true;
  nestedRuleSets.forEach((MirroredEntity<RuleSet> ruleSet) {
    var result = editRuleSet(ruleSet, editConfig, subTransaction);
    if (result != RemovalResult.removedAll) removedAll = false;
  });

  if (removedAll) {
    directive.remove(editConfig.mode, trans);
  } else {
    subTransaction.commit();
  }
}
