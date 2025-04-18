/*
 * Copyright 2018 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#ifndef IINSTRUMENT_H
#define IINSTRUMENT_H

#ifdef __cplusplus
#include <cstdint>
#include "IRenderableAudio.h"

class IInstrument: public IRenderableAudio {

public:
    virtual bool setOutputFormat(int32_t sampleRate, bool isStereo) = 0;
    virtual void handleMidiEvent(uint8_t status, uint8_t data1, uint8_t data2) = 0;

    // reset() should reset any state. It does not need to shut off all the MIDI notes, since
    // BaseScheduler handles that.
    virtual void reset() = 0;
};

#endif
#endif //IINSTRUMENT_H
