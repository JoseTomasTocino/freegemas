#include "log.h"

string Log::ToString(TLogLevel T){
    switch(T){
    case logERROR:
        return "ERROR";
        break;
    case logWARNING:
        return "WARNING";
        break;
    case logINFO:
        return "INFO";
        break;
    case logDEBUG:
    default:
        return "DEBUG";
        break;
    }
}
string Log::cRojo = "\033[31m";
string Log::cVerde =  "\033[32m";
string Log::cAmar = "\033[33m";
string Log::cAzul = "\033[34m";
string Log::cLila = "\033[35m";

string Log::nRojo = "\033[01;31m";
string Log::nVerde =  "\033[01;32m";
string Log::nAmar = "\033[01;33m";
string Log::nAzul = "\033[01;34m";
string Log::nLila = "\033[01;35m";

string Log::bRojo = "\033[1m\033[01;41m";
string Log::bVerde =  "\033[1m\033[01;42m";
string Log::bAmar = "\033[1m\033[01;43m";
string Log::bAzul = "\033[1m\033[01;44m";
string Log::bLila = "\033[1m\033[01;45m";



string Log::cDef = "\033[00m";


string Log::CON(string s){
    return cVerde + "[++ Constructor] " + s + cDef;
}

string Log::DES(string s){
    return cRojo + "[-- Destructor] " + s + cDef;
}

std::ostringstream& Log::Get(TLogLevel level)
{

    os << "[" << ToString(level) << "] ";
    return os;
}

Log::~Log(){
    os << Log::cDef << std::endl;
    if(salida){
        fprintf(stderr, "%s", os.str().c_str());
        fflush(stderr);
    }
}

bool Log::salida = true;
