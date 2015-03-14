// Copyright (C) 2012 José Tomás Tocino García <theom3ga@gmail.com>

// Autor: José Tomás Tocino García

// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 2
// of the License, or (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
// 02110-1301, USA.

#ifndef _DRAWINGQUEUE_H_
#define _DRAWINGQUEUE_H_

#include <map>
#include <SDL.h>
#include <SDL_image.h>

#include "log.h"

namespace GoSDL {

    struct DrawingQueueOperation
    {
        SDL_Texture * mTexture;
        SDL_Rect mDstRect;
        double mAngle;
        Uint8 mAlpha;
        SDL_Color mColor;
    };


    /**
     * Represents a drawing queue, where the Drawable objects will be drawn
     * depending on their depth (which is the key of the map).
     */

    class DrawingQueue : private std::multimap<float, DrawingQueueOperation>
    {
    public:

        /// Adds a new drawable element to the drawing queue in the selected depth
        void draw(float z, DrawingQueueOperation operation)
        {
            insert(std::pair<float, DrawingQueueOperation>(z, operation));
        }

    private:
        friend class Window;
    };

    // Iterator for the DrawingQueue
    typedef std::multimap<float, DrawingQueueOperation>::const_iterator DrawingQueueIterator;

}

#endif /* _DRAWINGQUEUE_H_ */
