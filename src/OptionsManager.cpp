#include "OptionsManager.h"

#include "Util.h"

void OptionsManager::loadResources()
{
    optionsDir = getPrefPath();

    loadOptions();
}

void OptionsManager::writeOptions()
{
    std::string optionsPath = optionsDir + optionsFile;
    std::ofstream optionsStream(optionsPath, std::ios::binary);
    optionsStream << options;
    optionsStream.close();
}

void OptionsManager::loadOptions()
{
    std::ifstream optionsStream;
    std::string optionsPath = optionsDir + optionsFile;
    optionsStream.open(optionsPath, std::ios::in);

    Json::CharReaderBuilder builder;
    JSONCPP_STRING errs;
    parseFromStream(builder, optionsStream, &options, &errs);
    optionsStream.close();
}

void OptionsManager::setHighscoreTimetrial(int score) {
    options["highscoreTimetrial"] = score;
    writeOptions();
}

void OptionsManager::setHighscoreEndless(int score) {
    options["highscoreEndless"] = score;
    writeOptions();
}

void OptionsManager::setMusicEnabled(bool value) {
    options["musicEnabled"] = value;
    writeOptions();
}

void OptionsManager::setSoundEnabled(bool value) {
    options["soundEnabled"] = value;
    writeOptions();
}

void OptionsManager::setFullscreenEnabled(bool value) {
    options["fullscreenEnabled"] = value;
    writeOptions();
}

int OptionsManager::getHighscoreTimetrial() {
    return options.get("highscoreTimetrial", 0).asInt();
}

int OptionsManager::getHighscoreEndless() {
    return options.get("highscoreEndless", 0).asInt();
}

bool OptionsManager::getMusicEnabled() {
    return options.get("musicEnabled", true).asBool();
}

bool OptionsManager:: getSoundEnabled() {
    return options.get("soundEnabled", true).asBool();
}

bool OptionsManager:: getFullscreenEnabled() {
    return options.get("fullscreenEnabled", false).asBool();
}
