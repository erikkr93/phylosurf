import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ncbi_taxonomy_explorer/utils/wav_encoder.dart';

void main() {
  group('encodeFloat32SamplesToWav', () {
    test('writes a valid 44-byte canonical PCM WAV header for 24 kHz mono', () {
      const sampleRate = 24000;
      final samples = Float32List(10);
      final wav = encodeFloat32SamplesToWav(samples, sampleRate);
      final view = ByteData.sublistView(wav);

      expect(wav.length, 44 + samples.length * 2);

      // RIFF / WAVE / fmt / data FourCC markers
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(view.getUint32(4, Endian.little), 36 + samples.length * 2);
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(String.fromCharCodes(wav.sublist(12, 16)), 'fmt ');
      expect(view.getUint32(16, Endian.little), 16); // PCM chunk size
      expect(view.getUint16(20, Endian.little), 1); // PCM audio format
      expect(view.getUint16(22, Endian.little), 1); // Mono channels
      expect(view.getUint32(24, Endian.little), sampleRate);
      expect(view.getUint32(28, Endian.little), sampleRate * 2); // ByteRate
      expect(view.getUint16(32, Endian.little), 2); // BlockAlign
      expect(view.getUint16(34, Endian.little), 16); // BitsPerSample
      expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');
      expect(view.getUint32(40, Endian.little), samples.length * 2);
    });

    test('handles empty samples with a valid 44-byte header and 0 data bytes',
        () {
      final wav = encodeFloat32SamplesToWav(Float32List(0), 24000);
      final view = ByteData.sublistView(wav);

      expect(wav.length, 44);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(view.getUint32(4, Endian.little), 36);
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(String.fromCharCodes(wav.sublist(12, 16)), 'fmt ');
      expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');
      expect(view.getUint32(40, Endian.little), 0);
    });

    test('clamps out-of-range samples and treats NaN as zero', () {
      // Short buffer (< 10 ms at 24 kHz) bypasses fade so raw clamping is exact.
      final samples = Float32List.fromList([
        2.5,
        -3.0,
        double.nan,
        double.infinity,
        double.negativeInfinity,
        0.5,
        -0.5,
        0.0,
      ]);

      final wav = encodeFloat32SamplesToWav(samples, 24000);
      final view = ByteData.sublistView(wav);

      expect(view.getInt16(44 + 0, Endian.little), 32767);
      expect(view.getInt16(44 + 2, Endian.little), -32767);
      expect(view.getInt16(44 + 4, Endian.little), 0);
      expect(view.getInt16(44 + 6, Endian.little), 32767);
      expect(view.getInt16(44 + 8, Endian.little), -32767);
      expect(view.getInt16(44 + 10, Endian.little), (0.5 * 32767.0).round());
      expect(view.getInt16(44 + 12, Endian.little), (-0.5 * 32767.0).round());
      expect(view.getInt16(44 + 14, Endian.little), 0);
    });

    test('applies 5 ms linear fade-in and fade-out when enough samples exist',
        () {
      const sampleRate = 24000;
      const fadeSamples = 120; // 5 ms at 24 kHz
      const totalSamples = 600; // 25 ms
      final samples = Float32List(totalSamples)..fillRange(0, totalSamples, 1.0);

      final wav = encodeFloat32SamplesToWav(samples, sampleRate);
      final view = ByteData.sublistView(wav);

      int pcmAt(int index) => view.getInt16(44 + index * 2, Endian.little);

      // Endpoints smoothly start and end at 0.
      expect(pcmAt(0), 0);
      expect(pcmAt(totalSamples - 1), 0);

      // Midpoint of fade-in and fade-out is approximately half amplitude.
      expect(pcmAt(fadeSamples ~/ 2), closeTo(32767 ~/ 2, 2));
      expect(
        pcmAt(totalSamples - 1 - (fadeSamples ~/ 2)),
        closeTo(32767 ~/ 2, 2),
      );

      // Interior samples after fade-in and before fade-out are full scale.
      expect(pcmAt(fadeSamples), 32767);
      expect(pcmAt(totalSamples ~/ 2), 32767);
      expect(pcmAt(totalSamples - 1 - fadeSamples), 32767);

      // Fade-in is monotonically increasing; fade-out monotonically decreasing.
      for (var i = 1; i < fadeSamples; i++) {
        expect(pcmAt(i), greaterThan(pcmAt(i - 1)));
      }
      for (var i = totalSamples - fadeSamples; i < totalSamples; i++) {
        expect(pcmAt(i), lessThan(pcmAt(i - 1)));
      }
    });

    test('rejects non-positive sample rates', () {
      expect(
        () => encodeFloat32SamplesToWav(Float32List(4), 0),
        throwsArgumentError,
      );
      expect(
        () => encodeFloat32SamplesToWav(Float32List(4), -16000),
        throwsArgumentError,
      );
    });
  });
}
