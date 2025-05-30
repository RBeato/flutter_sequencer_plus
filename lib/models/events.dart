import 'dart:typed_data';

const SCHEDULER_EVENT_SIZE = 16;
const SCHEDULER_EVENT_DATA_OFFSET = 8;
const MIDI_STATUS_NOTE_ON = 144;
const MIDI_STATUS_NOTE_OFF = 128;

/// Remember to keep SchedulerEvent.cpp in sync with this file.

/// The base class for Events. All events have a beat, which is used determine
/// when they will be handled.
abstract class SchedulerEvent {
  static const MIDI_EVENT = 0;
  static const VOLUME_EVENT = 1;

  SchedulerEvent({
    required this.beat,
    required this.type,
  });

  double beat;
  final int type;

  ByteData serializeBytes(int sampleRate, double tempo, int correctionFrames) {
    final data = ByteData(SCHEDULER_EVENT_SIZE);
    final us = ((1 / tempo) * beat * 60000000).round();
    final frame = ((us * sampleRate) / 1000000).round() + correctionFrames;

    data.setUint32(0, frame, Endian.host);
    data.setUint32(4, type, Endian.host);

    return data;
  }
}

/// Describes an event that will trigger a MIDI event.
class MidiEvent extends SchedulerEvent {
  MidiEvent({
    required super.beat,
    required this.midiStatus,
    required this.midiData1,
    required this.midiData2,
  }) : super(type: SchedulerEvent.MIDI_EVENT);

  final int midiStatus;
  final int midiData1;
  final int midiData2;

  @override
  ByteData serializeBytes(int sampleRate, double tempo, int correctionFrames) {
    final data = super.serializeBytes(sampleRate, tempo, correctionFrames);

    data.setUint8(SCHEDULER_EVENT_DATA_OFFSET, midiStatus);
    data.setUint8(SCHEDULER_EVENT_DATA_OFFSET + 1, midiData1);
    data.setUint8(SCHEDULER_EVENT_DATA_OFFSET + 2, midiData2);

    return data;
  }

  static MidiEvent ofNoteOn({
    required double beat,
    required int noteNumber,
    required int velocity,
  }) {
    if (noteNumber > 127 || noteNumber < 0) {
      throw 'noteNumber must be in range 0-127';
    }
    if (velocity > 127 || velocity < 0) throw 'Velocity must be in range 0-127';

    return MidiEvent(
      beat: beat,
      midiStatus: 144,
      midiData1: noteNumber,
      midiData2: velocity,
    );
  }

  static MidiEvent ofNoteOff({
    required double beat,
    required int noteNumber,
  }) {
    if (noteNumber > 127 || noteNumber < 0) {
      throw 'noteNumber must be in range 0-127';
    }

    return MidiEvent(
      beat: beat,
      midiStatus: 128,
      midiData1: noteNumber,
      midiData2: 0,
    );
  }

  static MidiEvent cc({
    required double beat,
    required int ccNumber,
    required int ccValue,
  }) {
    if (ccNumber > 127 || ccNumber < 0) throw 'ccNumber must be in range 0-127';
    if (ccValue > 127 || ccValue < 0) throw 'ccValue must be in range 0-127';

    return MidiEvent(
      beat: beat,
      midiStatus: 0xB0,
      midiData1: ccNumber,
      midiData2: ccValue,
    );
  }

  static MidiEvent pitchBend({
    required double beat,
    required double value,
  }) {
    if (value > 1 || value < -1) throw 'value must be in range -1 to 1';

    final intValue = (((value + 1) / 2) * 16383).round();
    final midiData1 = intValue >> 7;
    final midiData2 = intValue & 0x7F;

    return MidiEvent(
      beat: beat,
      midiStatus: 0xE0,
      midiData1: midiData1,
      midiData2: midiData2,
    );
  }
}

/// Describes an event that will trigger a volume change.
class VolumeEvent extends SchedulerEvent {
  VolumeEvent({
    required super.beat,
    required this.volume,
  }) : super(type: SchedulerEvent.VOLUME_EVENT);

  final double? volume;

  VolumeEvent withFrame(int frame) {
    return VolumeEvent(
      beat: beat,
      volume: volume,
    );
  }

  @override
  ByteData serializeBytes(int sampleRate, double beat, int correctionFrames) {
    final data = super.serializeBytes(sampleRate, beat, correctionFrames);

    data.setFloat32(SCHEDULER_EVENT_DATA_OFFSET, volume!, Endian.host);

    return data;
  }
}
