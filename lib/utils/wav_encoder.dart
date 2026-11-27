import 'dart:typed_data';

const int _kWavHeaderBytes = 44;
const int _kMonoChannels = 1;
const int _kBitsPerSample = 16;
const int _kBytesPerSample = _kBitsPerSample ~/ 8;
const int _kPcmAudioFormat = 1;
const double _kFadeDurationSeconds = 0.005;

/// Encodes normalized mono floating-point audio [samples] in `[-1.0, 1.0]` at
/// [sampleRate] Hz into a canonical 16-bit signed little-endian PCM WAV byte
/// buffer (`RIFF` / `WAVE` / `fmt ` / `data`).
///
/// Out-of-range samples are clamped to `[-1.0, 1.0]` and `NaN` values are
/// treated as `0.0`. When enough samples exist (at least 10 ms), a gentle 5 ms
/// linear fade-in and fade-out is applied to avoid speaker clicks or pops.
/// Empty [samples] produces a valid 44-byte WAV header with 0 data bytes.
Uint8List encodeFloat32SamplesToWav(Float32List samples, int sampleRate) {
  if (sampleRate <= 0) {
    throw ArgumentError.value(
      sampleRate,
      'sampleRate',
      'Sample rate must be positive.',
    );
  }

  final sampleCount = samples.length;
  final dataByteLength = sampleCount * _kBytesPerSample;
  final totalByteLength = _kWavHeaderBytes + dataByteLength;

  final bytes = Uint8List(totalByteLength);
  final view = ByteData.sublistView(bytes);

  // RIFF chunk descriptor
  bytes[0] = 0x52; // 'R'
  bytes[1] = 0x49; // 'I'
  bytes[2] = 0x46; // 'F'
  bytes[3] = 0x46; // 'F'
  view.setUint32(4, 36 + dataByteLength, Endian.little);
  bytes[8] = 0x57; // 'W'
  bytes[9] = 0x41; // 'A'
  bytes[10] = 0x56; // 'V'
  bytes[11] = 0x45; // 'E'

  // fmt sub-chunk
  bytes[12] = 0x66; // 'f'
  bytes[13] = 0x6D; // 'm'
  bytes[14] = 0x74; // 't'
  bytes[15] = 0x20; // ' '
  view.setUint32(16, 16, Endian.little); // PCM sub-chunk size
  view.setUint16(20, _kPcmAudioFormat, Endian.little);
  view.setUint16(22, _kMonoChannels, Endian.little);
  view.setUint32(24, sampleRate, Endian.little);
  view.setUint32(
    28,
    sampleRate * _kMonoChannels * _kBytesPerSample,
    Endian.little,
  );
  view.setUint16(32, _kMonoChannels * _kBytesPerSample, Endian.little);
  view.setUint16(34, _kBitsPerSample, Endian.little);

  // data sub-chunk
  bytes[36] = 0x64; // 'd'
  bytes[37] = 0x61; // 'a'
  bytes[38] = 0x74; // 't'
  bytes[39] = 0x61; // 'a'
  view.setUint32(40, dataByteLength, Endian.little);

  if (sampleCount == 0) {
    return bytes;
  }

  final fadeSamples = (sampleRate * _kFadeDurationSeconds).round();
  final applyFade = fadeSamples > 0 && sampleCount >= fadeSamples * 2;

  for (var i = 0; i < sampleCount; i++) {
    var value = samples[i].toDouble();
    if (value.isNaN) {
      value = 0.0;
    } else if (value > 1.0) {
      value = 1.0;
    } else if (value < -1.0) {
      value = -1.0;
    }

    if (applyFade) {
      if (i < fadeSamples) {
        value *= i / fadeSamples;
      } else {
        final fromEnd = sampleCount - 1 - i;
        if (fromEnd < fadeSamples) {
          value *= fromEnd / fadeSamples;
        }
      }
    }

    final pcm16 = (value * 32767.0).round().clamp(-32768, 32767);
    view.setInt16(_kWavHeaderBytes + (i * _kBytesPerSample), pcm16, Endian.little);
  }

  return bytes;
}
