#include "State.h"

#include "log.h"

State::State(Game * p) : mGame(p)
{
    lDEBUG << Log::CON("State");
}

State::~State()
{
    lDEBUG << Log::DES("State");
}
