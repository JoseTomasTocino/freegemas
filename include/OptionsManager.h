#ifndef OPTIONS_MANAGER_H
#define OPTIONS_MANAGER_H

#include <string>
#include <fstream>
#include <sys/stat.h>
#include <json/json.h>

class OptionsManager
{
    public:
        void loadResources();

        void setHighscoreTimetrial(int score);
        void setHighscoreEndless(int score);
        void setMusicEnabled(bool value);
        void setSoundEnabled(bool value);

        int getHighscoreTimetrial();
        int getHighscoreEndless();
        int getMusicEnabled();
        int getSoundEnabled();

    private:
        const std::string optionsFile = "options.json";

        Json::Value options;

        void writeOptions();
        void loadOptions();

        std::string getOptionsDir();
};

#endif