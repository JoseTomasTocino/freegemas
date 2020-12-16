/**
 * @file stateJuego.h
 *
 * @author José Tomás Tocino García
 * @date 2010
 *
 * Archivo para la clase de juego principal
 *
 * Copyright (C) 2010 José Tomás Tocino García <theom3ga@gmail.com>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
 * 02110-1301, USA.
 */


#ifndef _STATEGAMEENDLESS_H_
#define _STATEGAMEENDLESS_H_

#include "StateGame.h"

using namespace std;

class StateGameEndless : public StateGame{

public:

    StateGameEndless(Game * p);

    void update();
};

#endif /* _STATEGAMEENDLESS_H_ */
