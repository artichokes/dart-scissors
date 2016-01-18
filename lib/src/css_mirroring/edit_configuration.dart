library scissors.src.css_mirroring.edit_configuration;

import 'transformer.dart';
export 'transformer.dart' show Direction, flipDirection;

/// Indicates which parts of a CSS must be retained.
enum RetentionMode {
  /// Keep parts of CSS which are direction-independent eg: color and width.
  keepBidiNeutral,

  /// Keep direction dependent parts of original CSS eg: margin.
  keepOriginalBidiSpecific,

  /// to keep direction dependent parts of flipped CSS.
  keepFlippedBidiSpecific
}

class EditConfiguration {
  final RetentionMode mode;
  final Direction targetDirection;

  const EditConfiguration(this.mode, this.targetDirection);
}
