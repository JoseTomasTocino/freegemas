#include "OptionsManager.h"

void OptionsManager::loadResources()
{
    std::string optionsDir = getOptionsDir();

    // Make sure the directory exists
    mkdir(optionsDir.c_str(), 0755);

    loadOptions();
}

std::string OptionsManager::getOptionsDir() 
{
    std::string optionsPath;

    #ifdef __vita__
        optionsPath = "ux0:/data/freegemas/";
    #else
        char *xdgConfHome = getenv("XDG_CONFIG_HOME");
        if (xdgConfHome) {
            optionsPath = std::string(xdgConfHome) + "/freegemas/";
        } else {
            char *home = getenv("HOME");
            if (home) {
                optionsPath = std::string(home) + "/.config/freegemas/";
            } else {
                optionsPath = "./";
            }
        }
    #endif

    return optionsPath;
}

void OptionsManager::writeOptions()
{
    std::string optionsPath = getOptionsDir() + optionsFile;
    std::ofstream optionsStream(optionsPath, std::ios::binary);
    optionsStream << options;
    optionsStream.close();
}

void OptionsManager::loadOptions()
{
    std::ifstream optionsStream;
    std::string optionsPath = getOptionsDir() + optionsFile;
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

int OptionsManager::getHighscoreTimetrial() {
    return options.get("highscoreTimetrial", 0).asInt();
}

int OptionsManager::getHighscoreEndless() {
    return options.get("highscoreEndless", 0).asInt();
}

int OptionsManager::getMusicEnabled() {
    return options.get("musicEnabled", true).asBool();
}

int OptionsManager:: getSoundEnabled() {
    return options.get("soundEnabled", true).asBool();
}
