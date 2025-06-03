#ifndef SFIZZ_HPP
#define SFIZZ_HPP

#include <string>
#include <cstddef>

namespace sfz {

class Sfizz {
public:
    Sfizz();
    ~Sfizz();
    
    bool loadSfzFile(const std::string& path);
    bool loadSfzString(const std::string& path, const std::string& text);
    bool loadScalaFile(const std::string& path);
    bool loadScalaString(const std::string& text);
    
    void setSampleRate(float sampleRate);
    void setSamplesPerBlock(int samplesPerBlock);
    
    void noteOn(int delay, int noteNumber, int velocity);
    void noteOff(int delay, int noteNumber, int velocity);
    void cc(int delay, int ccNumber, int ccValue);
    void pitchWheel(int delay, int pitch);
    
    void renderBlock(float** buffers, size_t numFrames, int numOutputs = 2);
    
    int getNumRegions() const;
    
private:
    class Impl;
    Impl* pImpl;
};

} // namespace sfz

#endif // SFIZZ_HPP