const INITIAL_STEP_COUNT = 8;
const INITIAL_TEMPO = 240.0;
const INITIAL_IS_LOOPING = false;
const DEFAULT_VELOCITY = 0.75;

// General MIDI drum map: 36=Kick, 38=Snare, 42=Closed HH, 46=Open HH
// Testing different note for last column since CB (56) might not work in all SF2s
const ROW_LABELS_DRUMS = ['HH', 'S', 'K', 'Cr'];  // Changed CB to Cr (Crash)
const ROW_PITCHES_DRUMS = [42, 38, 36, 49];  // Using standard MIDI: 42=Closed HH, 49=Crash

const ROW_LABELS_PIANO = ['B', 'C3', 'D', 'E', 'F', 'G', 'A', 'B', 'C'];
const ROW_PITCHES_PIANO = [59, 60, 62, 64, 65, 67, 69, 71, 72];
