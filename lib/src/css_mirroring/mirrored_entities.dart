library scissors.src.css_mirroring.mirrored_entities;

import 'package:quiver/check.dart';
import 'package:csslib/visitor.dart';

import 'buffered_transaction.dart';
import 'edit_configuration.dart' show EditConfiguration, RetentionMode;
import 'entity.dart';

class MirroredEntity<T extends TreeNode> {
  final MirroredEntities<T> _entities;
  final int index;
  final MirroredEntity parent;
  MirroredEntity(this._entities, this.index, this.parent) {
    checkState(original.runtimeType == flipped.runtimeType,
        message: () => 'Mismatching entity types: '
            'original is ${original.runtimeType}, '
            'flipped is ${flipped.runtimeType}');
  }

  void remove(RetentionMode mode, BufferedTransaction trans) =>
      choose(mode).remove(trans);

  Entity<T> choose(RetentionMode mode) {
    switch (mode) {
      case RetentionMode.keepFlippedBidiSpecific:
        return flipped;
      case RetentionMode.keepOriginalBidiSpecific:
        return original;
      case RetentionMode.keepBidiNeutral:
        throw new ArgumentError('Invalid choice: $mode');
    }
  }

  Entity<T> get original =>
      new Entity<T>(_entities.originalSource, _entities.originals, index, parent?.original);

  Entity<T> get flipped =>
      new Entity<T>(_entities.flippedSource, _entities.flippeds, index, parent?.flipped);

  MirroredEntity<T> get next => index < _entities.originals.length - 1
      ? new MirroredEntity<T>(_entities, index + 1, parent)
      : null;

  MirroredEntities<dynamic> getChildren(List<dynamic> getEntityChildren(T value)) {
    return new MirroredEntities(
        _entities.originalSource, getEntityChildren(original.value),
        _entities.flippedSource, getEntityChildren(flipped.value),
        parent: this);
  }
}

class MirroredEntities<T extends TreeNode> {
  final String originalSource;
  final List<T> originals;

  final String flippedSource;
  final List<T> flippeds;

  final MirroredEntity parent;

  MirroredEntities(
      this.originalSource, this.originals,
      this.flippedSource, this.flippeds,
      {this.parent}) {
    assert(originals.length == flippeds.length);
  }

  get length => originals.length;

  void forEach(void process(MirroredEntity<T> entity)) {
    for (int i = 0; i < originals.length; i++) {
      process(new MirroredEntity<T>(this, i, parent));
    }
  }
}
