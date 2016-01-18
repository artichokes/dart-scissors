library scissors.src.css_mirroring.buffered_transaction;

import 'package:source_maps/refactor.dart' show TextEditTransaction;

class _Edit {
  final int start, end;
  final String text;
  _Edit(this.start, this.end, this.text);
}

class BufferedTransaction {
  final BufferedTransaction _parentTransaction;
  final TextEditTransaction _textEditTransaction;

  List<_Edit> _edits = <_Edit>[];

  BufferedTransaction._(this._parentTransaction) : _textEditTransaction = null;
  BufferedTransaction(this._textEditTransaction) : _parentTransaction = null;

  BufferedTransaction createSubTransaction() => new BufferedTransaction._(this);

  void edit(int start, int end, String text) =>
      _edits.add(new _Edit(start, end, text));

  void reset() {
    _edits.clear();
  }

  void commit() {
    var parent = _parentTransaction ?? _textEditTransaction;
    for (var edit in _edits) {
      parent.edit(edit.start, edit.end, edit.text);
    }
  }

  get length => _edits.length;
}
