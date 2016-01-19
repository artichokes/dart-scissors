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
library scissors.src.css_mirroring.mirrored_entities;

import 'package:quiver/check.dart';
import 'package:csslib/visitor.dart' show TreeNode;

import 'buffered_transaction.dart';
import 'edit_configuration.dart';
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

  Entity<T> choose(RetentionMode mode) =>
      mode == RetentionMode.keepFlippedBidiSpecific ? flipped : original;

  Entity<T> get original => new Entity<T>(
      _entities.originalSource, _entities.originals, index, parent?.original);

  Entity<T> get flipped => new Entity<T>(
      _entities.flippedSource, _entities.flippeds, index, parent?.flipped);

  MirroredEntities<dynamic> getChildren(
      List<dynamic> getEntityChildren(T value)) {
    return new MirroredEntities(
        _entities.originalSource,
        getEntityChildren(original.value),
        _entities.flippedSource,
        getEntityChildren(flipped.value),
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
      this.originalSource, this.originals, this.flippedSource, this.flippeds,
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
