library scissors.src.css_mirroring.util_functions;

import 'package:csslib/visitor.dart';

bool isDirectionInsensitive(TreeNode node) => node is CharsetDirective ||
    node is FontFaceDirective ||
    node is ImportDirective ||
    node is NamespaceDirective;

bool hasNestedRuleSets(TreeNode node) =>
    node is MediaDirective || node is HostDirective;
