/// Measured part coverage plus a deliberately approximate, session-only ETA.
/// No token-count percentage or countdown is fabricated for the first part.
class ExtractionProgress {
  int total = 0, completed = 0, inputCharacters = 0;
  int _completedAtMs = 0;
  String _modelKey = '';
  String? _sampleModel;
  int? _sampleChars, _sampleParts;
  double? _samplePartMs;
  void start(String modelKey, int characters) {
    _modelKey = modelKey;
    inputCharacters = characters;
    total = completed = _completedAtMs = 0;
  }

  void boundary(int nextPart, int parts, int elapsedMs) {
    if (parts < 1) return;
    total = parts;
    final done = (nextPart - 1).clamp(0, parts);
    if (done > completed) {
      completed = done;
      _completedAtMs = elapsedMs;
    }
  }

  double? get fraction => total == 0 ? null : completed / total;
  int? remainingSeconds(int elapsedMs) {
    if (total == 0 || completed >= total) return null;
    double? estimate;
    if (completed > 0 && _completedAtMs > 0) {
      estimate = _completedAtMs / completed * total;
    } else if (_sampleModel == _modelKey &&
        _sampleParts == total &&
        _sampleChars != null &&
        inputCharacters >= _sampleChars! * .7 &&
        inputCharacters <= _sampleChars! * 1.4) {
      estimate = _samplePartMs! * total;
    }
    if (estimate == null || elapsedMs >= estimate) return null;
    final seconds = ((estimate - elapsedMs) / 1000).ceil();
    // Avoid implying second-by-second accuracy for a CPU/thermal-dependent job.
    final quantum = seconds < 60 ? 5 : 10;
    return ((seconds / quantum).ceil() * quantum).clamp(5, 86400);
  }

  void finish(int elapsedMs, {required bool successful}) {
    if (!successful || total == 0) return;
    completed = total;
    _sampleModel = _modelKey;
    _sampleChars = inputCharacters;
    _sampleParts = total;
    _samplePartMs = elapsedMs / total;
  }
}
