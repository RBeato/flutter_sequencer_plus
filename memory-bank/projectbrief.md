# Project Brief: flutter_sequencer

## Overview
flutter_sequencer is a Flutter plugin for music sequencing, designed to provide powerful audio sequencing capabilities in Flutter applications. This project enables the creation of multi-track sequences of notes and automation that play on sampler instruments, with support for various sound formats.

## Core Requirements
1. Create a fully functional audio sequencing plugin compatible with Flutter
2. Support SFZ format instrument playback using the sfizz library
3. Support SoundFont (SF2) format instruments
4. Support iOS AudioUnit instruments
5. Provide robust multi-track sequencing capabilities with precise timing
6. Ensure proper volume automation and MIDI CC control
7. Enable playback control including play, pause, stop, loop, and position setting

## Goals
- Maintain compatibility with both Android and iOS platforms
- Ensure thread-safe native audio engine implementation
- Provide a clean, intuitive API for Flutter developers
- Optimize performance for modern devices
- Enable real-time note triggering and pattern sequencing
- Support looping and tempo control
- Allow dynamic track creation and instrument loading

## Project Scope
This project involves:
1. Native audio engine implementation for both Android and iOS
2. Integration with sfizz library for SFZ format support
3. Implementation of SoundFont (SF2) support
4. Creating a unified Dart API for the plugin
5. Building sample applications demonstrating sequencer functionality
6. Supporting various sound formats and instrument types
7. Implementing thread-safe audio processing

## Success Criteria
1. The plugin successfully plays multi-track sequences on both Android and iOS
2. Real-time audio triggering works with minimal latency
3. SFZ and SF2 instruments load and play correctly
4. Looping and tempo control function as expected
5. Volume automation and MIDI CC events work properly
6. The API is well-documented and easy to use
7. Example applications demonstrate all key features 